# frozen_string_literal: true

require_relative "typst"

module Archsight
  module Pdf
    # The facts of a resource that is not a page, as Typst markup: its properties (annotations) and its relations in
    # both directions. Structure comes from alignment and light rules, not from boxes: a muted label column, rows
    # divided by hairlines, related annotations kept together, and the resources of a relation flowing in columns
    # instead of one long comma-separated line.
    class ResourceSheet
      SKIP = %w[architecture/description architecture/diagram architecture/tags].freeze
      LONG = 400 # characters; longer single-line values still sit in the table, wrapped, up to MAX
      MAX = 2000
      RULE = "0.4pt + theme.muted.lighten(75%)" # as the rule under the rows of every other table
      NAMES_IN_COLUMNS = 4 # from this many resources a relation lists them in two columns

      # @param markdown [#call] `(String) -> Typst`, renders markdown the way the document does
      def initialize(resource, markdown:)
        @resource = resource
        @markdown = markdown
      end

      # @return [Array<String>] the sections (heading and content) of the properties, none if there are none
      def properties
        short, long = annotations.partition { |key, value| table_value?(key, value) }
        parts = []
        parts << "#heading(level: 1)[#{Typst.str("Properties")}]\n\n#{property_table(short)}" unless short.empty?
        long.each { |key, value| parts << long_value(key, value) }
        parts
      end

      # @return [Array<String>] the sections of the outgoing and the incoming relations
      def relations
        out = outgoing
        incoming = self.incoming
        return [] if out.empty? && incoming.empty?

        parts = ["#heading(level: 1)[#{Typst.str("Relations")}]"]
        parts << "#heading(level: 2)[#{Typst.str("Outgoing")}]\n\n#{relation_table(out)}" unless out.empty?
        parts << "#heading(level: 2)[#{Typst.str("Incoming")}]\n\n#{caption("Resources that point to this one; the relation is read from their side.")}\n\n#{relation_table(incoming)}" unless incoming.empty?
        parts
      end

      # `dependsOn` -> "depends on"
      def self.humanize(verb)
        verb.to_s.gsub(/([a-z0-9])([A-Z])/, '\1 \2').downcase
      end

      private

      def klass = @resource.class

      def annotations
        @resource.annotations.reject { |key, value| SKIP.include?(key) || value.to_s.strip.empty? }
      end

      # Multi-line and markdown values are text, not table cells
      def table_value?(key, value)
        !value.to_s.include?("\n") && !%w[markdown multiline].include?(klass.annotation_format(key).to_s)
      end

      def display(key, value)
        text = value.to_s
        text = text.split(",").map(&:strip).reject(&:empty?).join(", ") if klass.annotation_matching(key)&.list?
        text.length > MAX ? "#{text[0, MAX]}…" : text
      end

      # Annotations of one namespace (`git/...`, `lifecycle/...`) stay together, separated from the next by a gap
      def property_table(pairs)
        grouped = pairs.group_by { |key, _| key.split("/").first }.values
        cells = grouped.each_with_index.flat_map do |group, index|
          gap = index.zero? ? [] : ["table.cell(colspan: 2, stroke: none, inset: 3pt)[]"]
          gap + group.flat_map do |key, value|
            ["[#text(fill: theme.muted)[#{Typst.str(klass.annotation_title(key))}]]", "[#{Typst.str(display(key, value))}]"]
          end
        end
        "#table(columns: (30%, 1fr), stroke: (x, y) => (bottom: #{RULE}), inset: (x: 0pt, y: 5pt), #{cells.join(", ")})"
      end

      def long_value(key, value)
        body = klass.annotation_format(key).to_s == "markdown" ? @markdown.call(value.to_s) : multiline(value.to_s)
        "#heading(level: 2)[#{Typst.str(klass.annotation_title(key))}]\n\n#{body}"
      end

      def multiline(text)
        text.lines.map { |line| Typst.str(line.chomp) }.join("#linebreak()")
      end

      # { verb => { kind => [instances] } }
      def outgoing = @resource.relations_grouped

      # incoming comes as { kind => { verb => [instances] } }, shown like the outgoing ones
      def incoming
        @resource.references_grouped.each_with_object({}) do |(kind, verbs), by_verb|
          verbs.each { |verb, instances| (by_verb[verb] ||= {})[kind] = instances }
        end.sort.to_h
      end

      # The relation (said once for all of its kinds), the kind, and the names of the resources in one or two columns
      def relation_table(by_verb)
        cells = by_verb.flat_map do |verb, kinds|
          kinds.each_with_index.flat_map do |(kind, instances), index|
            row = []
            row << "table.cell(rowspan: #{kinds.size})[#text(weight: \"semibold\")[#{Typst.str(self.class.humanize(verb))}]]" if index.zero?
            row << "[#pad(right: 8pt, text(fill: theme.muted)[#{Typst.str(breakable(kind))}])]"
            row << "[#{names(instances)}]"
          end
        end
        "#table(columns: (17%, 24%, 1fr), stroke: (x, y) => (bottom: #{RULE}), inset: (x: 0pt, y: 5pt), #{cells.join(", ")})"
      end

      def names(instances)
        list = instances.map(&:name).uniq.sort.map { |name| "[#{Typst.str(breakable(name))}]" }
        columns = list.size >= NAMES_IN_COLUMNS ? "1fr, 1fr" : "1fr"
        "#grid(columns: (#{columns},), column-gutter: 10pt, row-gutter: 4pt, #{list.join(", ")})"
      end

      # Names have no spaces: allow a line break after each `:` and between camel-case words (no visible change)
      def breakable(name)
        name.gsub(":", ":\u200B").gsub(/([a-z0-9])([A-Z])/, "\\1\u200B\\2")
      end

      def caption(text)
        "#text(size: 8.5pt, fill: theme.muted)[#{Typst.str(text)}]"
      end
    end
  end
end
