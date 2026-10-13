# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"
require "yaml"
require "archsight/import"
require_relative "progress"

# Base class for import handlers
#
# Subclasses must implement the #execute method to perform the actual import.
# Use the helper methods to read configuration, validate environment, and write output.
class Archsight::Import::Handler
  attr_reader :import_resource, :database, :resources_dir, :progress, :shared_writer, :owned_outputs

  # Whether the handler generates child imports (`import_yaml`). An import that depends on a pattern
  # (`import/dependsOn: Import:Repo:*`) waits for such a handler on its first run, before it has a `generates` record
  # that tells which imports it creates. Override in handlers that generate imports.
  def self.generates_imports?
    false
  end

  # @param import_resource [Archsight::Resources::Import] The import resource to execute
  # @param database [Archsight::Database] The database instance
  # @param resources_dir [String] Root resources directory
  # @param progress [Archsight::Import::Progress] Progress reporter
  # @param shared_writer [Archsight::Import::SharedFileWriter] Thread-safe file writer for concurrent output
  def initialize(import_resource, database:, resources_dir:, progress: nil, shared_writer: nil)
    @import_resource = import_resource
    @database = database
    @resources_dir = resources_dir
    @progress = progress || Archsight::Import::Progress.new
    @shared_writer = shared_writer
    @tracked_resources = []
    @owned_outputs = []
  end

  # The directory the git-based handlers clone repositories into (`import/config/cacheRoot`, else `import.cache_root`
  # of the user configuration or ARCHSIGHT_IMPORT_CACHE_ROOT, else ~/.cache/archsight/git), so an importer of the
  # resources repository finds the same clones
  # @return [String] absolute path
  def cache_root
    File.expand_path(Archsight::Import.cache_root(config("cacheRoot")))
  end

  # Execute the import. Must be implemented by subclasses.
  # @raise [NotImplementedError] if not overridden
  def execute
    raise NotImplementedError, "#{self.class}#execute must be implemented"
  end

  # Get a configuration value from import/config/* annotations
  # @param key [String] Configuration key (without the import/config/ prefix)
  # @param default [Object, nil] Default value if not set
  # @return [String, nil] The configuration value
  def config(key, default: nil)
    import_resource.annotations["import/config/#{key}"] || default
  end

  # Get a path setting with `~` expanded, so `~/.cache/archsight/...` is a path in the home directory
  # and not a directory named `~` below the working directory. The value in the Import resource stays
  # as written (generated files keep the portable form), only the handler works with the expanded path.
  # @param key [String] Configuration key (without the import/config/ prefix)
  # @return [String, nil] The absolute path, nil if the setting is missing
  def config_path(key)
    value = config(key)
    value && File.expand_path(value)
  end

  # Get all configuration values as a hash
  # @return [Hash] Configuration key-value pairs
  def config_all
    import_resource.annotations.each_with_object({}) do |(key, value), hash|
      next unless key.start_with?("import/config/")

      config_key = key.sub("import/config/", "")
      hash[config_key] = value
    end
  end

  # Compute a hash of the import's configuration for cache invalidation
  # @return [String] 16-character hex hash
  def compute_config_hash
    config_data = {
      handler: import_resource.annotations["import/handler"],
      config: import_resource.annotations.select { |k, _| k.start_with?("import/config/") }.sort.to_h
    }
    Digest::SHA256.hexdigest(config_data.to_json)[0, 16]
  end

  # Generate a marker Import for this handler with generated/at timestamp and config hash
  # Used for caching - call at end of execute() to persist the execution timestamp. It also records the hash of the
  # files in `import/config/inputs` and the files written with #write_file, so call it after writing them.
  # @return [Hash] Import resource hash ready for YAML serialization
  def self_marker
    annotations = {
      "generated/at" => Time.now.utc.iso8601,
      "generated/configHash" => compute_config_hash
    }
    inputs_hash = Archsight::Import.inputs_hash(import_resource, resources_dir)
    annotations["generated/inputsHash"] = inputs_hash if inputs_hash
    annotations["generated/outputs"] = owned_outputs.uniq.sort.join(",") if owned_outputs.any?
    {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => import_resource.name,
        "annotations" => annotations
      },
      "spec" => {}
    }
  end

  # Write a whole file that belongs to this import alone, such as a page (Markdown) next to the generated YAML.
  # The file is recorded in the self marker (`generated/outputs`): the cache is invalid while it is missing, and a
  # file of an earlier run that is not written again is deleted.
  # @param rel_path [String] path relative to the resources directory
  # @param content [String]
  # @return [String] the absolute path
  # @raise [ArgumentError] for a path outside the resources directory
  def write_file(rel_path, content)
    full_path = Archsight::Import.resources_path(resources_dir, rel_path)
    raise ArgumentError, "#{rel_path} is outside the resources directory" unless full_path

    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
    record_output(rel_path)
    full_path
  end

  # Record a file this import wrote by other means (a command, a library) as its own output (see #write_file)
  # @param rel_path [String] path relative to the resources directory
  # @raise [ArgumentError] for a path outside the resources directory
  def record_output(rel_path)
    full_path = Archsight::Import.resources_path(resources_dir, rel_path)
    raise ArgumentError, "#{rel_path} is outside the resources directory" unless full_path

    @owned_outputs << Pathname.new(full_path).relative_path_from(File.expand_path(resources_dir)).to_s
  end

  # Write YAML content to the output path
  # @param content [String] YAML content to write
  # @param filename [String, nil] Output filename (overrides import/outputPath filename)
  # @return [String] Path to the written file
  #
  # Output location is determined by import/outputPath annotation:
  #   - Relative to resources_dir (e.g., "generated/repositories.yaml")
  #   - If filename parameter is provided, it replaces the filename from outputPath
  #   - If no outputPath, falls back to resources_dir/generated with import name as filename
  #
  # When shared_writer is available, uses thread-safe append for concurrent writes.
  # @param content [String] YAML content to write
  # @param filename [String, nil] Output filename (overrides import/outputPath filename)
  # @param sort_key [String, nil] Key for sorting in shared files (default: import name)
  def write_yaml(content, filename: nil, sort_key: nil)
    output_path = import_resource.annotations["import/outputPath"]

    full_path = if output_path
                  base = File.join(resources_dir, output_path)
                  if filename
                    # Replace filename portion with provided filename
                    File.join(File.dirname(base), filename)
                  else
                    base
                  end
                else
                  # Fallback to resources_dir/generated
                  File.join(resources_dir, "generated", filename || "#{safe_filename(import_resource.name)}.yaml")
                end

    if @shared_writer
      # Use thread-safe shared writer for concurrent execution
      # Default sort key is import name for stable output ordering
      key = sort_key || import_resource.name
      @shared_writer.append_yaml(full_path, content, sort_key: key, producer: import_resource.name)
    else
      # Direct write for non-concurrent mode
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end

    full_path
  end

  # Generate a resource YAML hash with standard metadata
  # @param kind [String] Resource kind (e.g., "TechnologyArtifact")
  # @param name [String] Resource name
  # @param annotations [Hash] Resource annotations
  # @param spec [Hash] Resource spec (relations)
  # @return [Hash] Resource hash ready for YAML serialization
  def resource_yaml(kind:, name:, annotations: {}, spec: {})
    @tracked_resources << { kind: kind, name: name }
    {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => kind,
      "metadata" => {
        "name" => name,
        "annotations" => annotations.merge(
          "generated/script" => import_resource.name,
          "generated/at" => Time.now.utc.iso8601
        )
      },
      "spec" => spec
    }
  end

  # Generate an Import resource YAML hash for child imports
  # @param name [String] Import resource name
  # @param handler [String] Handler name
  # @param config [Hash] Configuration annotations (added as import/config/*)
  # @param annotations [Hash] Additional annotations (added directly)
  # @return [Hash] Import resource hash ready for YAML serialization
  #
  # NOTE: generated/at is NOT set here - it's only set by the self_marker when
  # the child import actually executes. This ensures caching works correctly
  # regardless of file loading order.
  #
  # Dependencies are not specified here - they are derived from the `generates`
  # relation on the parent import (tracked via write_generates_meta).
  def import_yaml(name:, handler:, config: {}, annotations: {})
    @tracked_resources << { kind: "Import", name: name }
    all_annotations = {
      "import/handler" => handler,
      "generated/script" => import_resource.name
    }

    # Add direct annotations (e.g., import/outputPath)
    all_annotations.merge!(annotations)

    # Add config annotations with prefix
    config.each do |key, value|
      all_annotations["import/config/#{key}"] = value.to_s
    end

    {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => name,
        "annotations" => all_annotations
      },
      "spec" => {}
    }
  end

  # Convert multiple resource hashes to YAML string with document separators
  # @param resources [Array<Hash>] Array of resource hashes
  # @return [String] YAML string with --- separators
  def resources_to_yaml(resources)
    resources.map { |r| YAML.dump(r) }.join
  end

  # Write generates meta record for this Import
  # Call at end of execute() to persist tracking of generated resources
  # Appends to the output file rather than overwriting
  def write_generates_meta
    return if @tracked_resources.empty?

    meta = generates_meta_record(@tracked_resources)
    output_path = import_resource.annotations["import/outputPath"]

    full_path = if output_path
                  File.join(resources_dir, output_path)
                else
                  File.join(resources_dir, "generated", "#{safe_filename(import_resource.name)}.yaml")
                end

    if @shared_writer
      @shared_writer.append_yaml(full_path, YAML.dump(meta), sort_key: "#{import_resource.name}:generates",
                                                             producer: import_resource.name)
    else
      # Append to existing file
      File.open(full_path, "a") { |f| f.write(YAML.dump(meta)) }
    end
  end

  private

  # Create meta record for Import with generates relations
  # @param resources [Array<Hash>] Array of tracked resources with :kind and :name
  # @return [Hash] Import resource hash with generates spec
  def generates_meta_record(resources)
    grouped = resources.group_by { |r| r[:kind] }

    generates_spec = {}
    grouped.each do |kind, items|
      kind_key = kind_to_relation_key(kind)
      generates_spec[kind_key] = items.map { |r| r[:name] }
    end

    {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => { "name" => import_resource.name },
      "spec" => { "generates" => generates_spec }
    }
  end

  # Convert resource kind to relation key
  # @param kind [String] Resource kind (e.g., "TechnologyArtifact")
  # @return [String] Relation key (e.g., "technologyArtifacts")
  def kind_to_relation_key(kind)
    case kind
    when "TechnologyArtifact" then "technologyArtifacts"
    when "ApplicationInterface" then "applicationInterfaces"
    when "DataObject" then "dataObjects"
    when "Import" then "imports"
    when "BusinessActor" then "businessActors"
    else
      # Fallback: convert CamelCase to camelCase plural
      "#{kind[0].downcase}#{kind[1..]}s"
    end
  end

  # Convert a name to a safe filename
  # @param name [String] Resource name
  # @return [String] Safe filename
  def safe_filename(name)
    name.gsub(/[^a-zA-Z0-9_-]/, "_")
  end
end
