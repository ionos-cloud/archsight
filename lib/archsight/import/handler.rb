# frozen_string_literal: true

require "fileutils"
require "yaml"
require "archsight/import"
require_relative "progress"

# Base class for import handlers
#
# Subclasses must implement the #execute method to perform the actual import.
# Use the helper methods to read configuration, validate environment, and write output.
class Archsight::Import::Handler
  attr_reader :import_resource, :database, :resources_dir, :progress, :shared_writer

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

  # Get all configuration values as a hash
  # @return [Hash] Configuration key-value pairs
  def config_all
    import_resource.annotations.each_with_object({}) do |(key, value), hash|
      next unless key.start_with?("import/config/")

      config_key = key.sub("import/config/", "")
      hash[config_key] = value
    end
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
      @shared_writer.append_yaml(full_path, content, sort_key: key)
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
  # @param depends_on [Array<String>] Names of imports this depends on
  # @return [Hash] Import resource hash ready for YAML serialization
  def import_yaml(name:, handler:, config: {}, annotations: {}, depends_on: [])
    all_annotations = {
      "import/handler" => handler,
      "generated/script" => import_resource.name,
      "generated/at" => Time.now.utc.iso8601
    }

    # Add direct annotations (e.g., import/outputPath)
    all_annotations.merge!(annotations)

    # Add config annotations with prefix
    config.each do |key, value|
      all_annotations["import/config/#{key}"] = value.to_s
    end

    spec = {}
    spec["dependsOn"] = { "imports" => depends_on } unless depends_on.empty?

    {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => name,
        "annotations" => all_annotations
      },
      "spec" => spec
    }
  end

  # Convert multiple resource hashes to YAML string with document separators
  # @param resources [Array<Hash>] Array of resource hashes
  # @return [String] YAML string with --- separators
  def resources_to_yaml(resources)
    resources.map { |r| YAML.dump(r) }.join
  end

  private

  # Convert a name to a safe filename
  # @param name [String] Resource name
  # @return [String] Safe filename
  def safe_filename(name)
    name.gsub(/[^a-zA-Z0-9_-]/, "_")
  end
end
