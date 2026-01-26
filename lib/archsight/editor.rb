# frozen_string_literal: true

require "yaml"
require_relative "resources"
require_relative "editor/file_writer"

module Archsight
  # Editor handles building and validating resources for the web editor
  class Editor
    # Build a resource hash from form params
    # @param kind [String] Resource kind (e.g., "TechnologyArtifact")
    # @param name [String] Resource name
    # @param annotations [Hash] Annotation key-value pairs
    # @param relations [Array<Hash>] Array of {verb:, kind:, names:[]} hashes
    #   where kind is the target class name (e.g., "TechnologyArtifact")
    # @return [Hash] Resource hash ready for YAML conversion
    def self.build_resource(kind:, name:, annotations: {}, relations: [])
      resource = {
        "apiVersion" => "architecture/v1alpha1",
        "kind" => kind,
        "metadata" => {
          "name" => name
        }
      }

      # Add annotations if any non-empty values exist
      filtered_annotations = filter_empty(annotations)
      resource["metadata"]["annotations"] = filtered_annotations unless filtered_annotations.empty?

      # Add spec with relations if any exist
      spec = build_spec(kind, relations)
      resource["spec"] = spec unless spec.empty?

      resource
    end

    # Validate resource params using annotation definitions
    # @param kind [String] Resource kind
    # @param name [String] Resource name
    # @param annotations [Hash] Annotation key-value pairs
    # @return [Hash] { valid: Boolean, errors: { field => [messages] } }
    def self.validate(kind, name:, annotations: {})
      klass = Archsight::Resources[kind]
      errors = {}

      # Validate name
      if name.nil? || name.strip.empty?
        errors["name"] = ["Name is required"]
      elsif name =~ /\s/
        errors["name"] = ["Name cannot contain spaces"]
      end

      # Validate annotations against their definitions
      klass.annotations.reject(&:pattern?).each do |ann|
        value = annotations[ann.key]
        next if value.nil? || value.to_s.strip.empty?

        ann_errors = ann.validate(value)
        errors[ann.key] = ann_errors if ann_errors.any?
      end

      { valid: errors.empty?, errors: errors }
    end

    # Generate YAML string from resource hash
    # Uses custom YAML dump that formats multiline strings with literal block scalars
    # @param resource_hash [Hash] Resource hash
    # @return [String] YAML string
    def self.to_yaml(resource_hash)
      visitor = Psych::Visitors::YAMLTree.create
      visitor << resource_hash

      # Walk the AST and apply scalar style for multiline strings
      ast = visitor.tree
      apply_block_scalar_style(ast)

      ast.yaml(nil, line_width: 80)
    end

    # Recursively apply literal block style for multiline strings in YAML AST
    # @param node [Psych::Nodes::Node] YAML AST node
    def self.apply_block_scalar_style(node)
      case node
      when Psych::Nodes::Scalar
        if node.value.is_a?(String)
          # Normalize Windows/old Mac line endings to Unix style
          node.value = node.value.gsub("\r\n", "\n").gsub("\r", "\n") if node.value.include?("\r")
          # Use literal block style for multiline strings
          node.style = Psych::Nodes::Scalar::LITERAL if node.value.include?("\n")
        end
      when Psych::Nodes::Sequence, Psych::Nodes::Mapping, Psych::Nodes::Document, Psych::Nodes::Stream
        node.children.each { |child| apply_block_scalar_style(child) }
      end
    end

    # Get editable annotations for a resource kind
    # Excludes pattern annotations, computed annotations, and annotations with editor: false
    # @param kind [String] Resource kind
    # @return [Array<Archsight::Annotations::Annotation>]
    def self.editable_annotations(kind)
      klass = Archsight::Resources[kind]
      return [] unless klass

      # Get all annotations except pattern annotations
      annotations = klass.annotations.reject(&:pattern?)

      # Filter out computed annotations
      computed_keys = klass.computed_annotations.map(&:key)
      annotations = annotations.reject { |a| computed_keys.include?(a.key) }

      # Filter out non-editable annotations
      annotations.reject { |a| a.editor == false }
    end

    # Get available relations for a resource kind
    # @param kind [String] Resource kind
    # @return [Array<Array>] Array of [verb, target_kind, target_class_name]
    def self.available_relations(kind)
      klass = Archsight::Resources[kind]
      return [] unless klass

      klass.relations
    end

    # Get unique verbs for a resource kind's relations
    # @param kind [String] Resource kind
    # @return [Array<String>]
    def self.relation_verbs(kind)
      available_relations(kind).map { |v, _, _| v.to_s }.uniq.sort
    end

    # Get valid target class names for a given verb (for UI display and instance lookup)
    # @param kind [String] Resource kind
    # @param verb [String] Relation verb
    # @return [Array<String>] Target class names (e.g., "TechnologyArtifact")
    def self.target_kinds_for_verb(kind, verb)
      # Relations structure is [verb, relation_name, target_class_name]
      available_relations(kind)
        .select { |v, _, _| v.to_s == verb.to_s }
        .map { |_, _, target_class| target_class.to_s }
        .uniq
        .sort
    end

    # Get relation name for a given verb and target class (for building spec)
    # @param kind [String] Source resource kind
    # @param verb [String] Relation verb
    # @param target_class [String] Target class name
    # @return [String, nil] Relation name (e.g., "technologyComponents")
    def self.relation_name_for(kind, verb, target_class)
      relation = available_relations(kind).find do |v, _, tc|
        v.to_s == verb.to_s && tc.to_s == target_class.to_s
      end
      return nil unless relation

      relation[1].to_s
    end

    # Get target class name for a given verb and relation name (reverse lookup)
    # @param kind [String] Source resource kind
    # @param verb [String] Relation verb
    # @param relation_name [String] Relation name (e.g., "businessActors")
    # @return [String, nil] Target class name (e.g., "BusinessActor")
    def self.target_class_for_relation(kind, verb, relation_name)
      relation = available_relations(kind).find do |v, rn, _|
        v.to_s == verb.to_s && rn.to_s == relation_name.to_s
      end
      return nil unless relation

      relation[2].to_s
    end

    class << self
      private

      # Filter out empty values from a hash and convert to plain Hash
      # (avoids !ruby/hash:Sinatra::IndifferentHash in YAML output)
      def filter_empty(hash)
        return {} if hash.nil?

        result = hash.reject { |_, v| v.nil? || v.to_s.strip.empty? }
        # Convert to plain Hash to avoid Ruby-specific YAML tags
        result.to_h
      end

      # Build spec hash from relations array
      # @param source_kind [String] The source resource kind
      # @param relations [Array<Hash>] Array of {verb:, kind:, names:[]} hashes
      #   where kind is the target class name (e.g., "TechnologyArtifact")
      # @return [Hash] Spec hash with proper relation_name keys
      def build_spec(source_kind, relations)
        return {} if relations.nil? || relations.empty?

        spec = {}
        relations.each { |rel| add_relation_to_spec(spec, source_kind, rel) }
        deduplicate_spec_values(spec)
      end

      def add_relation_to_spec(spec, source_kind, rel)
        verb, target_class, names = extract_relation_parts(rel)
        return if invalid_relation?(verb, target_class, names)

        relation_name = Archsight::Editor.relation_name_for(source_kind, verb, target_class)
        return unless relation_name

        spec[verb.to_s] ||= {}
        spec[verb.to_s][relation_name] ||= []
        spec[verb.to_s][relation_name].concat(names)
      end

      def extract_relation_parts(rel)
        verb = rel[:verb] || rel["verb"]
        target_class = rel[:kind] || rel["kind"]
        names = normalize_names(rel[:names] || rel["names"] || [])
        [verb, target_class, names]
      end

      def normalize_names(names)
        names = [names] unless names.is_a?(Array)
        names.map(&:to_s).reject(&:empty?)
      end

      def invalid_relation?(verb, target_class, names)
        verb.nil? || verb.to_s.strip.empty? ||
          target_class.nil? || target_class.to_s.strip.empty? ||
          names.empty?
      end

      def deduplicate_spec_values(spec)
        spec.transform_values { |kinds| kinds.transform_values(&:uniq) }
      end
    end
  end
end
