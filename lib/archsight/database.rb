# frozen_string_literal: true

require "yaml"
require_relative "graph"
require_relative "resources"
require_relative "page_loader"
require_relative "query"
require_relative "references"

module Archsight
  # LineReference combines a path and line reference
  class LineReference
    attr_accessor :path, :line_no

    def initialize(path, line_no)
      @path = path
      @line_no = line_no
    end

    def to_s
      "#{@path}:#{@line_no}"
    end

    def at_line(line_no)
      self.class.new(@path, line_no)
    end
  end

  # ResourceError is an error with a path and line no attached
  class ResourceError < StandardError
    attr_reader :ref, :message

    def initialize(msg, ref)
      super(msg)
      @message = msg
      @ref = ref
    end

    def to_s
      "#{ref}: #{super}"
    end
  end

  # Deprecation is a use of a renamed kind or relation key that was accepted under its old name
  Deprecation = Struct.new(:ref, :message) do
    def to_s
      "#{ref}: #{message}"
    end
  end

  # Database loads yaml files and folders to create an in-memory representation
  # of the structure. The loading and parsing of files will raise errors
  # if invalid data is passed.
  class Database
    attr_accessor :instances, :verbose, :verify, :compute_annotations, :only_kinds
    attr_reader :path, :deprecations

    def initialize(path, verbose: false, verify: true, compute_annotations: true, only_kinds: nil)
      @path = path
      @verbose = verbose
      @verify = verify
      @compute_annotations = compute_annotations
      @only_kinds = only_kinds
      @instances = {}
      @deprecations = []
    end

    def reload!
      @instances = {}
      @deprecations = []

      # load all resources
      Dir.glob(File.join(@path, "**/*.{yaml,md}")).each do |path|
        @current_ref = LineReference.new(path, 0)
        puts "parsing #{path}..." if @verbose
        File.extname(path) == ".md" ? load_page(path) : load_file(path)
      end

      verify! if @verify
      derive_references! if @verify
      compute_all_annotations! if @verify && @compute_annotations
    rescue Psych::SyntaxError => e
      # Wrap YAML syntax errors in ResourceError for consistent handling
      ref = LineReference.new(e.file || @current_ref&.path || "unknown", e.line || 0)
      Kernel.raise(ResourceError.new(e.problem || e.message, ref))
    end

    def instances_by_kind(kind)
      @instances[Archsight::Resources[kind]] || {}
    end

    def instance_by_kind(kind, instance)
      @instances[Archsight::Resources[kind]][instance]
    end

    # Collect unique annotation values across all instances of a kind
    def annotation_values(kind, annotation)
      instances = instances_by_kind(kind).values
      values = instances.flat_map { |inst| Array(annotation.value_for(inst)) }
      values.compact.uniq.sort
    end

    # Get filterable annotations with their values for a kind (excludes empty)
    def filters_for_kind(kind)
      klass = Archsight::Resources[kind]
      return [] unless klass

      klass.filterable_annotations
           .map { |a| [a, annotation_values(kind, a)] }
           .reject { |_, values| values.empty? }
    end

    # Execute a query string and return matching instances
    def query(query_string)
      q = Archsight::Query.parse(query_string)
      q.filter(self)
    end

    # Check if a specific instance matches a query
    def instance_matches?(instance, query_string)
      q = Archsight::Query.parse(query_string)
      q.matches?(instance, database: self)
    end

    private

    def create_valid_instance(obj)
      raise("invalid api version") if obj["apiVersion"] != "architecture/v1alpha1"

      kind = obj["kind"] || raise("kind not defined")
      klass = Archsight::Resources[kind] || raise("#{kind} is not a valid kind")
      accept_old_names(obj)
      inst = klass.new(obj, @current_ref)
      raise("metadata name of #{kind} not present") if inst.name.to_s.strip.empty?

      inst
    end

    # Documents may still use the old name of a renamed kind and the old relation keys. They are rewritten to the
    # current names here, so everything after loading only sees those, and each rewrite is kept as a deprecation
    # (reported by `archsight lint`).
    def accept_old_names(obj)
      kind = obj["kind"]
      current = Archsight::Resources.canonical(kind)
      if current != kind
        deprecate("kind '#{kind}' is renamed to '#{current}'")
        obj["kind"] = current
      end

      accept_old_annotations(obj)

      return unless obj["spec"].is_a?(Hash)

      obj["spec"].each do |verb, keys|
        next unless keys.is_a?(Hash)

        Archsight::Resources::RELATION_KEY_ALIASES.each do |old_key, new_key|
          next unless keys.key?(old_key)

          deprecate("relation key '#{old_key}' under '#{verb}' is renamed to '#{new_key}'")
          keys[new_key] = (Array(keys[new_key]) + Array(keys.delete(old_key))).uniq
        end
      end
    end

    # A renamed annotation key (page/confluence is now link/confluence) is moved to its new key
    def accept_old_annotations(obj)
      annotations = obj.dig("metadata", "annotations")
      return unless annotations.is_a?(Hash)

      Archsight::Resources::ANNOTATION_ALIASES.each do |old_key, new_key|
        next unless annotations.key?(old_key)

        deprecate("annotation '#{old_key}' is renamed to '#{new_key}'#{legacy_frontmatter_hint(old_key)}")
        value = annotations.delete(old_key)
        annotations[new_key] ||= value
      end
    end

    # In a page the annotation is a frontmatter key: `confluence:` is now `links: { confluence: ... }`
    def legacy_frontmatter_hint(old_key)
      return "" unless old_key.start_with?("page/")

      name = old_key.delete_prefix("page/")
      " (frontmatter `#{name}:` is now `links: { #{name}: <url> }`)"
    end

    def deprecate(message)
      @deprecations << Deprecation.new(@current_ref, "#{message} (the old name will be removed in a future release)")
    end

    # Whether a document of this kind is wanted by the only_kinds filter, whichever of its names either side uses
    def kind_wanted?(kind)
      return true unless @only_kinds

      @only_kinds.map { |k| Archsight::Resources.canonical(k) }.include?(Archsight::Resources.canonical(kind))
    end

    def load_file(path)
      File.open(path, "r") do |f|
        YAML.parse_stream(f) do |node|
          @current_ref = @current_ref.at_line(node.children.first.start_line)
          obj = node.to_ruby
          next unless obj # skip empty / unknown documents

          # Skip resources that don't match only_kinds filter
          next unless kind_wanted?(obj["kind"])

          self << create_valid_instance(obj)
        end
      end
    end

    # Load a markdown page; files without frontmatter are not pages and are ignored
    def load_page(path)
      return if @only_kinds && !@only_kinds.include?("Page")

      @current_ref = LineReference.new(path, 1)
      obj = PageLoader.build(path: path, source: File.read(path), ref: @current_ref)
      return unless obj

      inst = create_valid_instance(obj)
      if (existing = @instances.dig(inst.class, inst.name))
        raise("page name '#{inst.name}' is already used by #{existing.path_ref.path}; set a unique `name:` in the frontmatter")
      end

      self << inst
    end

    def <<(inst)
      inst.verify!
      klass = inst.class
      @instances[klass] ||= {}
      if (existing_inst = @instances[klass][inst.name])
        existing_inst.merge!(inst)
      else
        @instances[klass][inst.name] = inst
      end
    end

    # raise provides a helper for better error messages including current path and line no
    def raise(msg)
      Kernel.raise(ResourceError.new(msg, @current_ref))
    end

    # raise_for provides error messages with the instance's path reference
    def raise_for(inst, msg)
      Kernel.raise(ResourceError.new(msg, inst.path_ref))
    end

    # verify and resolve relations between resources
    def verify!
      @instances.each_value do |instances|
        instances.each_value do |inst|
          verify_instance_relations!(inst)
        end
      end
    end

    def verify_instance_relations!(inst)
      inst.class.declared_relations.each do |verb, kind, klass_name|
        rels = inst.relations(verb, kind).map do |rel_name|
          rel_klass = Archsight::Resources[klass_name] || raise_for(inst, "#{klass_name} is not a valid relation kind")
          kind_display = rel_klass.to_s.sub(/^Archsight::Resources::/, "")
          @instances[rel_klass] || raise_for(inst, "#{rel_name} is not defined as kind #{kind_display}")
          @instances[rel_klass][rel_name] || raise_for(inst, "#{rel_name} is not defined as kind #{kind_display}")
        end
        inst.set_relations(verb, kind, rels) unless rels.empty?
      end
    end

    # Adds the relations that the text and the diagrams of the resources imply (`mentions`, `depicts`), after all
    # written relations are resolved and before the computed annotations are calculated, which follow relations.
    def derive_references!
      Archsight::References.derive!(self)
    end

    # Compute all computed annotations for all instances
    def compute_all_annotations!
      manager = Archsight::Annotations::ComputedManager.new(self)
      manager.compute_all!
    end
  end
end
