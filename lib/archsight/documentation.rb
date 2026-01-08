# frozen_string_literal: true

require_relative "resources"
require_relative "template"

module Archsight
  # Documentation generates markdown documentation for architecture resources
  class Documentation
    # Layer display order (top to bottom)
    LAYER_ORDER = %w[motivation strategy business application technology].freeze

    # Layer display names
    LAYER_NAMES = {
      "motivation" => "Motivation Layer",
      "strategy" => "Strategy Layer",
      "business" => "Business Layer",
      "application" => "Application Layer",
      "technology" => "Technology Layer"
    }.freeze

    # Resource kinds to exclude from the diagram
    EXCLUDED_KINDS = %w[View].freeze

    @mermaid_cache = nil

    class << self
      attr_accessor :mermaid_cache

      # Generate mermaid flowchart diagram showing all resource types and relationships
      # Results are cached for performance
      # @return [String] Mermaid flowchart diagram
      def generate_mermaid_diagram
        return @mermaid_cache if @mermaid_cache

        @mermaid_cache = build_mermaid_diagram
      end

      # Clear the mermaid cache (call when resources change)
      def clear_cache
        @mermaid_cache = nil
      end

      # Build the mermaid diagram from resource definitions
      # Layer colors are defined in CSS (public/css/mermaid-layers.css)
      def build_mermaid_diagram
        lines = []
        lines << "flowchart TB"

        # Group resources by layer (excluding certain kinds)
        resources_by_layer = Hash.new { |h, k| h[k] = [] }
        Archsight::Resources.each do |kind_name|
          next if EXCLUDED_KINDS.include?(kind_name.to_s)

          klass = Archsight::Resources.const_get(kind_name)
          layer = klass.layer
          next unless LAYER_ORDER.include?(layer) # Skip resources in unlisted layers

          resources_by_layer[layer] << kind_name.to_s
        end

        # Generate subgraphs for each layer in order
        LAYER_ORDER.each do |layer|
          next unless resources_by_layer.key?(layer)

          kinds = resources_by_layer[layer].sort
          next if kinds.empty?

          lines << ""
          lines << "    subgraph #{layer.capitalize}[\"#{LAYER_NAMES[layer]}\"]"
          kinds.each do |kind|
            lines << "        #{kind}:::#{layer}"
          end
          lines << "    end"
        end

        # Collect all relations and deduplicate
        relations = collect_relations
        lines << ""
        relations.each do |from_kind, verb, to_kind|
          lines << "    #{from_kind} -->|#{verb}| #{to_kind}"
        end

        # Add click handlers for each kind
        lines << ""
        all_kinds = resources_by_layer.values.flatten
        all_kinds.sort.each do |kind_name|
          lines << "    click #{kind_name} \"/kinds/#{kind_name}\""
        end

        lines.join("\n")
      end

      # Collect all unique relations from resource definitions
      # @return [Array<Array>] Array of [from_kind, verb, to_kind] tuples
      def collect_relations
        relations = []
        seen = Set.new

        Archsight::Resources.each do |kind_name|
          # Skip excluded kinds
          next if EXCLUDED_KINDS.include?(kind_name.to_s)

          klass = Archsight::Resources.const_get(kind_name)
          # Skip kinds not in a displayed layer
          next unless LAYER_ORDER.include?(klass.layer)

          klass.relations.each do |verb, _relation_kind, target_klass|
            # Skip relations to excluded kinds
            next if EXCLUDED_KINDS.include?(target_klass.to_s)

            key = "#{kind_name}|#{verb}|#{target_klass}"
            next if seen.include?(key)

            seen.add(key)
            relations << [kind_name.to_s, verb.to_s.delete_prefix(":"), target_klass.to_s]
          end
        end

        relations.sort_by { |from, verb, to| [from, to, verb] }
      end

      def generate(kind_name)
        klass = Archsight::Resources[kind_name.to_s]
        raise "Unknown resource kind '#{kind_name}'" unless klass

        md = []
        md << "# #{kind_name}\n"
        md << klass.description if klass.description
        md << "\n## Annotations\n"
        md << generate_annotations_table(klass)
        md << "\n## Relations\n"
        md << generate_relations_table(klass)
        md << "\n## Example\n"
        md << "```yaml\n#{Archsight::Template.generate(kind_name)}```"
        md.compact.join("\n")
      end

      def generate_annotations_table(klass)
        annotations = klass.annotations.reject(&:pattern?)
        return "_No annotations defined._" if annotations.empty?

        rows = ["| Annotation | Description | Values |", "|------------|-------------|--------|"]
        annotations.each do |a|
          values = format_values(a)
          rows << "| `#{a.key}` | #{a.description || "-"} | #{values} |"
        end
        rows.join("\n")
      end

      def generate_relations_table(klass)
        return "_No relations defined._" if klass.relations.empty?

        rows = ["| Relation | Target | Kind |", "|----------|--------|------|"]
        klass.relations.each do |verb, kind, target_klass|
          rows << "| #{verb} | #{target_klass} | #{kind} |"
        end
        rows.join("\n")
      end

      def format_values(annotation)
        if annotation.enum
          annotation.enum.join(", ")
        elsif annotation.type
          annotation.type.to_s.split("::").last
        else
          "-"
        end
      end
    end
  end
end
