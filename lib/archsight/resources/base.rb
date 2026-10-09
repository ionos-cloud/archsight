# frozen_string_literal: true

require_relative "../annotations/annotation"

module Archsight
  module Resources
    # Base is the base for all assets, should not be used directly, only by inheritance
    class Base
      attr_accessor :raw, :path_ref, :references

      def self.inherited(subclass)
        super
        # Auto-register when class is defined
        Archsight::Resources.register(subclass)
      end

      def self.relation(verb, kind, klass_name)
        @declared_relations ||= [] #: Array[[Symbol, Symbol, String]]
        @declared_relations << [verb, kind, klass_name]
        @relations = nil
      end

      # The relations a resource of this kind may be written with in a file (`spec`)
      def self.declared_relations
        @declared_relations || []
      end

      # Every relation a resource of this kind can have: the declared ones and the derived ones (`mentions`,
      # `depicts`, see Archsight::References). Everything that follows relations (queries, graphs, impact analysis)
      # uses this; what lets a user write or choose relations uses declared_relations.
      def self.relations
        @relations ||= (declared_relations + Archsight::Resources::DERIVED_RELATIONS).freeze
      end

      # A kind may mark at most this many annotations as summary (see Base.annotation)
      MAX_SUMMARY_ANNOTATIONS = 3

      # Define an annotation using the Annotation class
      # `summary: true` marks it as a summary attribute: it is returned with every search hit of this kind.
      # `unique: true` makes it an identifier: its values (each element of a list) are unique among the resources
      # of the kind, which `archsight lint` checks, and it is shown as plain text, not as tags.
      def self.annotation(key, description: nil, filter: nil, title: nil, format: nil, enum: nil, sidebar: true,
                          type: nil, summary: false, editor: true, validator: nil, unique: false)
        options = { description: description, filter: filter, title: title, format: format, enum: enum,
                    sidebar: sidebar, type: type, summary: summary, editor: editor, validator: validator,
                    unique: unique }
        register_annotation(Archsight::Annotations::Annotation.new(key, options))
      end

      # Append an annotation definition, enforcing the limit of summary annotations per kind.
      # Annotations of included modules (include_annotations) come through here as well.
      def self.register_annotation(annotation)
        @annotations ||= [] #: Array[Archsight::Annotations::Annotation]
        if annotation.summary? && @annotations.count(&:summary?) >= MAX_SUMMARY_ANNOTATIONS
          raise ArgumentError,
                "#{name}: at most #{MAX_SUMMARY_ANNOTATIONS} annotations can be summary attributes, " \
                "cannot add #{annotation.key}"
        end

        @annotations << annotation
      end

      # Get all annotation definitions
      def self.annotations
        @annotations || []
      end

      # Define a computed annotation using a block
      # Computed annotations are calculated from related resources after the database is loaded.
      # Supports all the same options as regular annotations.
      # @param key [String] The annotation key (e.g., 'computed/total_cost')
      # @param description [String, nil] Human-readable description
      # @param filter [Symbol, nil] Filter type (:word, :list, or nil)
      # @param title [String, nil] Display title
      # @param format [Symbol, nil] Rendering format (:markdown, :asd, :tag_word, :tag_list)
      # @param enum [Array, nil] Allowed values
      # @param sidebar [Boolean] Show in sidebar (default false for computed)
      # @param type [Class, nil] Type for value coercion (Integer, Float, String)
      # @param summary [Boolean] Return the value with every search hit of this kind (default false, max 3 per kind)
      # @yield Block that computes the annotation value, evaluated in Evaluator context
      def self.computed_annotation(key, description: nil, filter: nil, title: nil, format: nil, enum: nil,
                                   sidebar: false, type: nil, summary: false, editor: true, &)
        require_relative "../annotations/computed"
        @computed_annotations ||= [] #: Array[Archsight::Annotations::Computed]
        @computed_annotations << Archsight::Annotations::Computed.new(key, description: description, type: type, &)

        # Also register as a regular annotation so it passes validation and is recognized
        options = { description: description, filter: filter, title: title, format: format, enum: enum,
                    sidebar: sidebar, type: type, summary: summary, editor: editor }
        register_annotation(Archsight::Annotations::Annotation.new(key, options))
      end

      # Get all computed annotation definitions
      def self.computed_annotations
        @computed_annotations || []
      end

      # Find annotation definition matching a key (handles patterns)
      def self.annotation_matching(key)
        annotations.find { |a| a.matches?(key) }
      end

      # Check if key matches any pattern annotation
      def self.matches_annotation_pattern?(key)
        annotations.any? { |a| a.pattern? && a.matches?(key) }
      end

      # Get filterable annotations as array of Annotation objects
      def self.filterable_annotations
        annotations.select(&:filterable?).reject(&:pattern?)
      end

      # Get the annotations marked as summary attributes (returned with search hits)
      def self.summary_annotations
        annotations.select(&:summary?).reject(&:pattern?)
      end

      def self.annotation_title(key)
        annotation_matching(key)&.title || key.split("/").last.capitalize
      end

      def self.annotation_format(key)
        annotation_matching(key)&.format
      end

      # The formats this kind defines for the given annotation keys, `{ "evidence/gaps" => "markdown" }` (keys without
      # a format are left out). The frontend shows each value accordingly.
      def self.annotation_formats(keys)
        formats = {} #: Hash[String, String]
        keys.each do |key|
          format = annotation_format(key)
          formats[key] = format.to_s if format
        end
        formats
      end

      def self.annotation_enum(key)
        annotation_matching(key)&.enum
      end

      def self.icon(icon_name = nil)
        if icon_name
          @icon = icon_name
        else
          @icon || "page" # default icon
        end
      end

      def self.layer(layer_name = nil)
        if layer_name
          @layer = layer_name
        else
          @layer || "other" # default layer
        end
      end

      def self.description(text = nil)
        if text
          @description = text
        else
          @description
        end
      end

      # Include annotation modules by symbol name
      # @example include_annotations :git, :architecture, :backup
      # @param names [Array<Symbol>] Symbols representing annotation modules (:git, :architecture, :backup, :generated)
      def self.include_annotations(*names)
        names.each do |name|
          # Convert snake_case to CamelCase (e.g., :git -> 'Git', :my_module -> 'MyModule')
          module_name = name.to_s.split("_").map(&:capitalize).join
          mod = Archsight::Annotations.const_get(module_name)
          include mod
        rescue NameError
          available = Archsight::Annotations.constants
                                            .select { |c| Archsight::Annotations.const_get(c).is_a?(Module) && Archsight::Annotations.const_get(c).respond_to?(:included) }
                                            .map { |c| ":#{c.to_s.gsub(/([a-z])([A-Z])/, '\1_\2').downcase}" }
                                            .sort
          Kernel.raise "Unknown annotation module :#{name}. Available: #{available.join(", ")}"
        end
      end

      def self.discovered_annotations
        @discovered_annotations ||= Set.new
      end

      def initialize(raw, path_ref)
        @raw = raw
        @path_ref = path_ref
        @references = []
        # Auto-discover annotation keys
        return unless annotations

        annotations.each_key do |key|
          self.class.discovered_annotations.add(key)
        end
      end

      def klass
        self.class.name.split("::").last
      end

      def kind
        @raw["kind"]
      end

      def name
        metadata["name"]
      end

      def annotations
        metadata["annotations"] || {}
      end

      # Set a computed annotation value
      # This writes to both the computed values cache and the annotations hash
      # so computed values are accessible via the normal annotations interface.
      # @param key [String] The annotation key
      # @param value [Object] The computed value
      def set_computed_annotation(key, value)
        @computed_values ||= {} #: Hash[String, untyped]
        @computed_values[key] = value
        # Write to annotations hash for query compatibility
        @raw["metadata"] ||= {}
        @raw["metadata"]["annotations"] = @raw["metadata"]["annotations"] || {} #: Hash[String, String]
        @raw["metadata"]["annotations"][key] = value
      end

      # Get a computed annotation value from the cache
      # @param key [String] The annotation key
      # @return [Object, nil] The computed value or nil
      def computed_annotation_value(key)
        @computed_values&.[](key)
      end

      def metadata
        @raw["metadata"] || {}
      end

      def spec
        @raw["spec"] || {}
      end

      def to_s
        "#<#{self.class} name=#{name}>"
      end

      def abandoned?
        annotations["activity/status"] == "abandoned"
      end

      def has_relations?
        spec.any? { |_verb, kinds| kinds.is_a?(Hash) && kinds.values.any? { |v| v.is_a?(Array) && v.any? } }
      end

      def verb_allowed?(verb)
        self.class.declared_relations.any? { |v, _, _| v.to_s == verb.to_s }
      end

      def verb_kind_allowed?(verb, kind)
        self.class.declared_relations.any? { |v, k, _| v.to_s == verb.to_s && k.to_s == kind.to_s }
      end

      def relations(verb, kind)
        (spec[verb.to_s] || {})[kind.to_s] || []
      end

      # Records a relation that is derived from this resource's text or diagram, not written in its file: the target
      # goes into `spec` where the relations of this verb are read (so queries and graphs see it like any other) and
      # learns about this resource as one that refers to it.
      def add_derived_relation(verb, target)
        key = Archsight::Resources::DERIVED_KEY.to_s
        spec_root = (@raw["spec"] ||= {}) #: Hash[String, untyped]
        by_key = (spec_root[verb.to_s] ||= {}) #: Hash[String, Array[Base]]
        by_key[key] ||= [] #: Array[Base]
        targets = by_key.fetch(key)
        return if targets.any? { |known| known.equal?(target) }

        targets << target
        target.referenced_by(self, verb.to_sym)
      end

      def set_relations(verb, kind, rels)
        spec[verb.to_s][kind.to_s] = rels
        rels.each { |rel| rel.referenced_by(self, verb) }
      end

      def referenced_by(inst, verb = nil)
        # Store reference with verb information for grouped display
        existing = @references.find { |r| r[:instance] == inst && r[:verb] == verb }
        @references << { instance: inst, verb: verb } unless existing
      end

      # Get references grouped by kind and verb for display (incoming)
      # Returns: { "Kind" => { "verb" => [instances...] } }
      def references_grouped
        grouped = {} #: Hash[String, Hash[untyped, Array[Base]]]
        @references.each do |ref|
          inst = ref[:instance]
          verb = ref[:verb]
          kind = inst.klass
          grouped[kind] ||= {}
          grouped[kind][verb] ||= [] #: Array[Base]
          grouped[kind][verb] << inst
        end
        # Sort by kind name, then by verb name
        grouped.sort.to_h.transform_values { |verbs| verbs.sort.to_h }
      end

      # Get outgoing relations grouped by verb and kind for display
      # Returns: { "verb" => { "Kind" => [instances...] } }
      def relations_grouped
        grouped = {} #: Hash[String, Hash[String, Array[Base]]]
        spec.each do |verb, kinds|
          next unless kinds.is_a?(Hash)

          kinds.each_value do |instances|
            next unless instances.is_a?(Array) && instances.any?

            instances.each do |inst|
              kind = inst.klass
              grouped[verb] ||= {}
              grouped[verb][kind] ||= [] #: Array[Base]
              grouped[verb][kind] << inst
            end
          end
        end
        # Sort by verb name, then by kind name
        grouped.sort.to_h.transform_values { |kinds| kinds.sort.to_h }
      end

      def verify!
        spec.each do |verb, kinds|
          raise "unknown verb #{verb}" unless verb_allowed?(verb)

          kinds.each_key do |kind, _|
            raise "unknown verb #{verb} / kind #{kind} combination" unless verb_kind_allowed?(verb, kind)
          end
        end
      end

      def merge!(inst)
        # NOTE: path reference is preserved from the original instance
        merged = Archsight::Helpers.deep_merge(@raw, inst.raw)
        union_list_annotations!(merged, inst.raw)
        @raw = merged
      end

      # Annotations hold strings, which replace each other on merge. The values of a list annotation (tags, aliases)
      # are joined instead, so two documents of one resource can each add to it.
      def union_list_annotations!(merged, other_raw)
        mine = @raw.dig("metadata", "annotations")
        theirs = other_raw.dig("metadata", "annotations")
        return unless mine.is_a?(Hash) && theirs.is_a?(Hash)

        theirs.each do |key, value|
          next unless mine[key].is_a?(String) && value.is_a?(String)
          next unless self.class.annotation_matching(key)&.list?

          values = (split_list(mine[key]) + split_list(value)).uniq
          merged["metadata"]["annotations"][key] = values.join(",")
        end
      end

      def split_list(text)
        text.split(/,|\n/).map(&:strip).reject(&:empty?)
      end

      # raise provides a helper for better error messages including current path and line no
      def raise(msg)
        Kernel.raise(Archsight::ResourceError.new(msg, @path_ref))
      end
    end
  end
end
