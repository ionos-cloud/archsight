# frozen_string_literal: true

require_relative "../../editor"
require_relative "form_builder"

module Archsight
  module Web
    module Editor
      # Shared helpers for editor routes
      module Helpers
        # Get form fields for a resource kind
        def editor_fields(kind)
          FormBuilder.fields_for(kind)
        end

        # Get available relations for a resource kind
        def available_relations(kind)
          Archsight::Editor.available_relations(kind)
        end

        # Extract annotations from JSON body or form params
        def extract_annotations(params)
          annotations = params["annotations"] || {}
          annotations.transform_values { |v| v.is_a?(String) ? v.strip : v }
        end

        # Parse relations from JSON array format
        # Accepts: [{ verb, kind, names: [...] }] or [{ verb, kind, name }]
        def parse_json_relations(relations_data)
          return [] unless relations_data.is_a?(Array)

          relations_data.each_with_object([]) do |rel, result|
            next unless rel.is_a?(Hash)

            parsed = parse_single_relation(rel)
            next unless parsed

            merge_relation(result, parsed)
          end
        end

        # Validate content hash for optimistic locking
        def validate_content_hash(instance, expected_hash)
          Archsight::Editor::ContentHasher.validate(
            path: instance.path_ref.path,
            start_line: instance.path_ref.line_no,
            expected_hash: expected_hash
          )
        end

        # Build form metadata response for a kind
        def build_form_metadata(kind, klass)
          {
            kind: kind,
            icon: klass.icon,
            layer: klass.layer,
            fields: serialize_fields(kind),
            relation_options: build_relation_options(kind),
            instances_by_kind: build_instances_by_kind(kind),
            inline_edit_enabled: settings.inline_edit_enabled
          }
        end

        # Extract relations from an existing instance into form format
        def extract_instance_relations(instance)
          relations = []

          instance.spec.each do |verb, relation_groups|
            next unless relation_groups.is_a?(Hash)

            relation_groups.each do |relation_name, targets|
              next unless targets.is_a?(Array)

              target_class = Archsight::Editor.target_class_for_relation(instance.kind, verb, relation_name)
              next unless target_class

              targets.each do |target|
                target_name = target.respond_to?(:name) ? target.name : target.to_s
                relations << { verb: verb, kind: target_class, name: target_name }
              end
            end
          end

          relations
        end

        private

        def parse_single_relation(rel)
          verb = (rel["verb"] || rel[:verb])&.to_s&.strip
          kind = (rel["kind"] || rel[:kind])&.to_s&.strip
          return if verb.nil? || verb.empty? || kind.nil? || kind.empty?

          names = extract_relation_names(rel)
          return if names.empty?

          { verb: verb, kind: kind, names: names }
        end

        def extract_relation_names(rel)
          names = rel["names"] || rel[:names]
          name = rel["name"] || rel[:name]

          if names.is_a?(Array)
            names.map(&:to_s).reject(&:empty?)
          elsif name
            [name.to_s.strip].reject(&:empty?)
          else
            []
          end
        end

        def merge_relation(relations, parsed)
          existing = relations.find { |r| r[:verb] == parsed[:verb] && r[:kind] == parsed[:kind] }
          if existing
            parsed[:names].each { |n| existing[:names] << n unless existing[:names].include?(n) }
          else
            relations << parsed
          end
        end

        def serialize_fields(kind)
          editor_fields(kind).map do |f|
            {
              key: f.key, title: f.title, description: f.description,
              input_type: f.input_type.to_s, options: f.options, step: f.step,
              required: f.required, code_language: f.code_language&.to_s
            }
          end
        end

        def build_relation_options(kind)
          available_relations(kind)
            .map { |v, _, k| { combo: "#{v}:#{k}", verb: v.to_s, target_kind: k.to_s } }
            .sort_by { |r| r[:combo] }
            .uniq { |r| r[:combo] }
        end

        def build_instances_by_kind(kind)
          target_kinds = build_relation_options(kind).map { |r| r[:target_kind] }.uniq
          target_kinds.each_with_object({}) do |k, h|
            h[k] = db.instances_by_kind(k).keys.sort
          rescue StandardError
            h[k] = []
          end
        end
      end
    end
  end
end
