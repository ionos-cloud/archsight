# frozen_string_literal: true

require "json"

module Archsight
  module Summary
    # The direct relations of a resource, both ways, as Related(verb, direction, resource); "out" = the resource
    # declares the relation, "in" = the other resource points at it
    Related = Struct.new(:verb, :direction, :resource)

    module Relations
      module_function

      def direct(instance)
        outgoing = instance.relations_grouped.flat_map do |verb, kinds|
          kinds.values.flatten.map { |target| Related.new(verb.to_s, "out", target) }
        end
        incoming = instance.references.map { |ref| Related.new(ref[:verb].to_s, "in", ref[:instance]) }
        (outgoing + incoming).uniq { |rel| [rel.verb, rel.direction, rel.resource.object_id] }
      end
    end

    # Builds the summary of one resource as markdown: what it is, the sections of its lens (each relation group with
    # a count and the first few resources as `[[Kind/Name]]` links, and the exact call that lists the rest) and a
    # pointer to the other layers that have related resources. Empty sections are not shown. The result is bounded: the
    # lists shrink and sections drop until it fits `max_chars`. Only the model is read, so it is reproducible.
    class Builder
      NOISE_KINDS = %w[Page PageMenu].freeze # followed only by an explicit verb, never through `*`
      DESCRIPTION_CHARS = 400
      FACTS = 6

      Group = Struct.new(:label, :resources, :call)
      Block = Struct.new(:title, :groups)

      def initialize(database, per_section: 5, max_chars: 6000)
        @db = database
        @per_section = [[per_section.to_i, 1].max, 20].min
        @max_chars = max_chars
      end

      # @param lens_layer [String, nil] the layer whose lens to use instead of the one of the resource's kind
      # @param source [Hash, nil] where the resource is defined: {source: "path:line", generated: bool}
      # @return [String] markdown
      def call(instance, lens_layer: nil, source: nil)
        @source = source
        lens = lens_layer || instance.class.layer
        sections = Lens.for(@db, lens, kind: lens_layer ? nil : instance.klass)
        blocks = sections.filter_map { |section| block_for(instance, section) }
        render_bounded(instance, lens, blocks)
      end

      private

      def render_bounded(instance, lens, blocks)
        limits = [@per_section, 3, 2, 1].uniq.select { |n| n <= @per_section }
        text = nil
        limits.each do |per|
          text = render(instance, lens, blocks, per)
          return text if text.length <= @max_chars
        end
        blocks = blocks.dup
        while blocks.length > 1 && text.length > @max_chars
          blocks.pop
          text = render(instance, lens, blocks, limits.last, omitted: true)
        end
        text
      end

      def render(instance, lens, blocks, per, omitted: false)
        lines = header(instance, lens)
        blocks.each do |block|
          lines << "" << "## #{block.title}"
          block.groups.each { |group| lines << group_line(group, per) }
        end
        lines.concat(other_layers(instance, lens))
        lines << "" << "_More sections were left out to keep this short; use the `relations` tool for the rest._" if omitted
        lines.join("\n")
      end

      def header(instance, lens)
        kind = instance.klass
        layer = instance.class.layer
        meta = ["**#{kind}**", "#{layer} layer"]
        meta << "viewed through the #{lens} lens" if lens != layer
        lines = ["# #{link(instance)}", meta.join(" · ")]
        lines << source_line if @source&.dig(:source)
        description = description_of(instance)
        lines << "" << description if description
        facts = facts_of(instance)
        lines << "" << facts.join(" · ") unless facts.empty?
        lines
      end

      def source_line
        note = @source[:generated] ? " (generated: change the importer or generator, not this file)" : ""
        "Defined in `#{@source[:source]}`#{note}"
      end

      # The opening of the description: its first paragraph up to a list, heading or code block, which stay in the
      # resource itself
      def description_of(instance)
        paragraph = instance.annotations["architecture/description"].to_s.strip.split(/\n\s*\n/).first.to_s
        lines = paragraph.lines.take_while { |line| !line.match?(/\A\s*([-*+]\s|\d+[.)]\s|\#|```)/) }
        text = lines.map(&:strip).join(" ").sub(/:\z/, "").strip
        return nil if text.empty?

        text.length > DESCRIPTION_CHARS ? "#{text[0, DESCRIPTION_CHARS - 1].rstrip}…" : text
      end

      # The summary attributes of the kind that have a value, as "Title: value"
      def facts_of(instance)
        instance.class.summary_annotations.filter_map do |annotation|
          value = Array(annotation.value_for(instance)).map(&:to_s).reject(&:empty?)
          next if value.empty?

          text = value.join(", ")
          "#{annotation.title}: #{text.length > 80 ? "#{text[0, 79]}…" : text}"
        end.first(FACTS)
      end

      def block_for(instance, section)
        groups = section.depth > 1 ? deep_groups(instance, section) : direct_groups(instance, section)
        groups.empty? ? nil : Block.new(section.title, groups)
      end

      def direct_groups(instance, section)
        matching(Relations.direct(instance), section).group_by(&:verb).sort.map do |verb, rels|
          entries = ordered(rels.map(&:resource))
          call = "relations(kind: #{instance.klass.to_json}, name: #{instance.name.to_json}, verb: #{verb.to_json}, direction: #{section.direction.to_json})"
          Group.new(verb, entries, call)
        end
      end

      # Resources reached in up to `depth` steps along the section's verbs, grouped by step, nearest first
      def deep_groups(instance, section)
        seen = {}.compare_by_identity
        seen[instance] = true
        frontier = [instance]
        (1..section.depth).filter_map do |step|
          reached = []
          frontier.each do |resource|
            matching(Relations.direct(resource), section).each do |rel|
              next if seen[rel.resource]

              seen[rel.resource] = true
              reached << rel.resource
            end
          end
          frontier = reached
          next if reached.empty?

          Group.new("#{section.verbs.join("/")} (step #{step})", ordered(reached), deep_call(instance, section))
        end
      end

      def deep_call(instance, section)
        verbs = section.all_verbs? ? "" : ", verbs: #{section.verbs.to_json}"
        "analyze_resource(kind: #{instance.klass.to_json}, name: #{instance.name.to_json}, impact: true, direction: #{section.direction.to_json}#{verbs}, depth: #{section.depth})"
      end

      def matching(relations, section)
        relations.select do |rel|
          next false unless rel.direction == section.direction
          next false if section.all_verbs? && NOISE_KINDS.include?(rel.resource.klass)

          section.all_verbs? || section.verbs.include?(rel.verb)
        end
      end

      # Resources with a description first (they explain themselves), then by name: reproducible
      def ordered(resources)
        resources.uniq(&:object_id).sort_by { |r| [r.annotations["architecture/description"].to_s.strip.empty? ? 1 : 0, r.name] }
      end

      def group_line(group, per)
        shown = group.resources.first(per)
        total = group.resources.length
        label = total > 1 ? "#{group.label} (#{total})" : group.label
        line = "- #{label}: #{shown.map { |r| link(r) }.join(", ")}"
        rest = total - shown.length
        rest.positive? ? "#{line}, +#{rest} more: `#{group.call}`" : line
      end

      # Layers other than the one the lens shows that have directly related resources
      def other_layers(instance, lens)
        by_layer = Relations.direct(instance).map(&:resource).uniq(&:object_id).group_by { |r| r.class.layer }
        by_layer = by_layer.reject { |layer, _| layer == lens || layer == "other" }
        return [] if by_layer.empty?

        lines = ["", "## Related in other layers"]
        Lens::DEFAULTS.each_key do |layer|
          resources = by_layer[layer] or next
          kinds = resources.group_by(&:klass).sort.map { |kind, list| "#{kind} #{list.length}" }.join(", ")
          lines << "- #{layer} (#{resources.length}): #{kinds}; `summary(kind: #{instance.klass.to_json}, name: #{instance.name.to_json}, lens: #{layer.to_json})`"
        end
        lines
      end

      def link(resource)
        "[[#{resource.klass}/#{resource.name}]]"
      end
    end
  end
end
