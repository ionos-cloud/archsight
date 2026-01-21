# frozen_string_literal: true

require "yaml"
require_relative "graph"
require_relative "resources"
require_relative "query"

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

  # Database loads yaml files and folders to create an in-memory representation
  # of the structure. The loading and parsing of files will raise errors
  # if invalid data is passed.
  class Database
    attr_accessor :instances, :verbose, :verify, :compute_annotations, :only_kinds

    def initialize(path, verbose: false, verify: true, compute_annotations: true, only_kinds: nil)
      @path = path
      @verbose = verbose
      @verify = verify
      @compute_annotations = compute_annotations
      @only_kinds = only_kinds
      @instances = {}
    end

    def reload!
      @instances = {}

      # load all resources
      Dir.glob(File.join(@path, "**/*.yaml")).each do |path|
        @current_ref = LineReference.new(path, 0)
        puts "parsing #{path}..." if @verbose
        load_file(path)
      end

      verify! if @verify
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
      inst = klass.new(obj, @current_ref)
      inst.name || raise("metadata name of #{kind} not present")
      inst
    end

    def load_file(path)
      File.open(path, "r") do |f|
        YAML.parse_stream(f) do |node|
          @current_ref = @current_ref.at_line(node.children.first.start_line)
          obj = node.to_ruby
          next unless obj # skip empty / unknown documents

          # Skip resources that don't match only_kinds filter
          next if @only_kinds && !@only_kinds.include?(obj["kind"])

          self << create_valid_instance(obj)
        end
      end
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
      inst.class.relations.each do |verb, kind, klass_name|
        rels = inst.relations(verb, kind).map do |rel_name|
          rel_klass = Archsight::Resources[klass_name] || raise_for(inst, "#{klass_name} is not a valid relation kind")
          kind_display = rel_klass.to_s.sub(/^Archsight::Resources::/, "")
          @instances[rel_klass] || raise_for(inst, "#{rel_name} is not defined as kind #{kind_display}")
          @instances[rel_klass][rel_name] || raise_for(inst, "#{rel_name} is not defined as kind #{kind_display}")
        end
        inst.set_relations(verb, kind, rels) unless rels.empty?
      end
    end

    # Compute all computed annotations for all instances
    def compute_all_annotations!
      manager = Archsight::Annotations::ComputedManager.new(self)
      manager.compute_all!
    end
  end
end
