# frozen_string_literal: true

require_relative "../markdown"
require_relative "../helpers/macros"
require_relative "../jira_settings"
require_relative "typst"

module Archsight
  module Pdf
    # Markdown (the dialect of Archsight::Markdown) as Typst markup.
    #
    # What a document refers to is resolved by the caller through hooks, so this class knows neither the database
    # nor the file system:
    #
    # - `image`:   `(src, alt) -> String | nil`, Typst markup for an embedded image (nil: left out, the alt text is shown)
    # - `diagram`: `(source) -> String`, Typst markup for an `asd` code block (default: the source as code)
    # - `label`:   `(target) -> String`, the text of a `[[Target]]` link without label (default: the target)
    # - `embeds`:  an object with `view_block(source)`, `requirements_block(source)` and `embed(reference)`, each
    #   returning Typst markup (never raising: what cannot be shown is a note). It makes the live content of a page, a
    #   ```view or ```requirements block and `![[Kind/Name]]` on a line of its own, part of the document. Without it
    #   those blocks are shown as written and an embed is its label.
    class Markdown
      include Typst

      SYMBOLS = {
        ndash: "–", mdash: "—", hellip: "…", laquo: "«", raquo: "»", laquo_space: "« ", raquo_space: " »",
        lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”"
      }.freeze
      STATUS_FILL = {
        "green" => "#d9f2e0", "yellow" => "#fff3cc", "red" => "#fde8e8", "blue" => "#ddeeff", "grey" => "#e8e8e8",
        "gray" => "#e8e8e8", "purple" => "#eadcf8"
      }.freeze
      EMBED = /\A!\[\[([^\]|]+)\]\]\z/
      # `![[Embed]]`, `[[Target|label]]` and the `{macro:arguments}` of the wiki (see Helpers::Macros)
      INLINE = /(!)?\[\[([^\]|]+)(?:\|([^\]]+))?\]\]|\{([a-z][a-z0-9-]*)(?::([^{}|\n]*))?\}/
      ALIGNMENT = { left: "left", center: "center", right: "right" }.freeze

      # @param heading_offset [Integer] added to the level of every heading
      def initialize(heading_offset: 0, image: nil, diagram: nil, label: nil, embeds: nil)
        @heading_offset = heading_offset
        @image = image
        @diagram = diagram
        @label = label
        @embeds = embeds
      end

      # @param inline [Boolean] for a table cell or list item: paragraphs are joined by a line break
      # @return [String] Typst markup
      def render(source, inline: false)
        out = blocks(Archsight::Markdown.document(source).root.children)
        inline ? out.gsub(/\n\n+/, " #linebreak() ") : out
      end

      private

      def blocks(elements)
        elements.filter_map { |node| block(node) }.join("\n\n")
      end

      def block(node)
        case node.type
        when :p then paragraph(node)
        when :header then "#heading(level: #{[node.options[:level] + @heading_offset, 6].min})[#{inlines(node.children)}]"
        when :codeblock then code(node.value, node.options[:lang])
        when :blockquote then "#quote(block: true)[#{blocks(node.children)}]"
        when :ul then "#list(#{items(node)})"
        when :ol then "#enum(#{items(node)})"
        when :hr then "#line(length: 100%, stroke: 0.5pt + luma(200))"
        when :table then table(node)
        when :blank, :html_element, :xml_comment then nil
        else inlines(node.children) unless node.children.empty?
        end
      end

      # A paragraph that is only an image is a figure, centred; one that is only embeds (one per line) is their content
      def paragraph(node)
        content = node.children.reject { |c| c.type == :text && c.value.strip.empty? }
        return image(content.first) if content.size == 1 && content.first.type == :img

        embeds = block_embeds(content)
        return embeds if embeds

        inlines(node.children)
      end

      def block_embeds(content)
        return nil unless @embeds && content.size == 1 && content.first.type == :text

        lines = content.first.value.lines.map(&:strip).reject(&:empty?)
        return nil unless lines.any? && lines.all? { |line| line.match?(EMBED) }

        lines.map { |line| @embeds.embed(line[EMBED, 1].strip) }.join("\n\n")
      end

      def items(list)
        list.children.map { |li| "[#{blocks(li.children)}]" }.join(", ")
      end

      def code(source, lang)
        case lang.to_s
        when "asd" then @diagram ? @diagram.call(source) : raw(source, lang)
        when "view" then @embeds ? @embeds.view_block(source) : raw(source, lang)
        when "requirements" then @embeds ? @embeds.requirements_block(source) : raw(source, lang)
        when "mermaid" then [note("Mermaid diagram, shown as a diagram in Archsight", fill: "#f2f2f2"), raw(source, lang)].join("\n\n")
        else raw(source, lang)
        end
      end

      def table(node)
        head, body = node.children.partition { |section| section.type == :thead }
        head_rows = head.flat_map(&:children).map { |tr| cells(tr, header: true) }
        body_rows = body.flat_map(&:children).map { |tr| cells(tr) }
        width = (head_rows + body_rows).map(&:size).max || 1
        header = head_rows.empty? ? "" : "table.header(#{head_rows.flatten.join(", ")}), "
        "#table(columns: #{width}, #{align(node, width)}#{header}#{body_rows.flatten.join(", ")})"
      end

      def align(node, width)
        alignment = Array(node.options[:alignment])
        return "" unless alignment.any? { |a| ALIGNMENT.key?(a) }

        "align: (#{Array.new(width) { |i| ALIGNMENT.fetch(alignment[i], "auto") }.join(", ")},), "
      end

      # The header cells are semibold, set on the cells (a show rule on the table header does not reach their text)
      def cells(row, header: false)
        row.children.map do |td|
          content = inlines(td.children)
          header ? "[#text(weight: \"semibold\")[#{content}]]" : "[#{content}]"
        end
      end

      def inlines(elements)
        elements.map { |node| inline(node) }.join
      end

      def inline(node)
        case node.type
        when :text then text(node.value)
        when :em then "#emph[#{inlines(node.children)}]"
        when :strong then "#strong[#{inlines(node.children)}]"
        when :codespan then "#raw(#{lit(node.value)})"
        when :a then "#link(#{lit(node.attr["href"])})[#{inlines(node.children)}]"
        when :br then "#linebreak()"
        when :img then image(node)
        when :entity then str(node.value.char)
        when :smart_quote, :typographic_sym then str(SYMBOLS.fetch(node.value, node.value.to_s))
        when :html_element then html(node)
        else inlines(node.children)
        end
      end

      def html(node)
        return "#linebreak()" if node.value == "br"

        checkbox(node) || inlines(node.children)
      end

      def checkbox(node)
        return unless node.value == "input" && node.attr["type"] == "checkbox"

        str(node.attr.key?("checked") ? "☑ " : "☐ ")
      end

      def image(node)
        src = node.attr["src"].to_s
        alt = node.attr["alt"].to_s
        @image&.call(src, alt) || "#emph[#{str(alt.empty? ? src : alt)}]"
      end

      # Plain text, in which wiki links, embeds and the macros of the wiki are replaced. A single newline in the source
      # is a soft break, a space as in CommonMark (a string literal would keep it as a line break); `<br>`, a backslash
      # or two trailing spaces are the hard breaks, which are their own nodes.
      def text(source)
        value = source.gsub(/[ \t]*\n[ \t]*/, " ")
        out = +""
        pos = 0
        value.scan(INLINE) do
          match = Regexp.last_match
          out << str(value[pos...match.begin(0)]) if match.begin(0) > pos
          out << (replacement(match) || str(match[0]))
          pos = match.end(0)
        end
        out << str(value[pos..]) if pos < value.length
        out
      end

      def replacement(match)
        match[2] ? link(match) : macro(match[4], match[5])
      end

      def link(match)
        label = match[3]&.strip || @label&.call(match[2].strip) || match[2].strip
        match[1] ? "#emph[#{str(label)}]" : str(label)
      end

      # A registered macro with valid arguments; nil leaves the text as written. What needs the running application
      # (`children`, `pagetree`) has no meaning on paper.
      def macro(name, arguments)
        handler = Helpers::Macros.handler(name)
        return nil unless handler

        value = handler.parse(arguments)
        return nil unless value

        case name
        when "status" then badge(value.text.upcase, STATUS_FILL.fetch(value.colour.to_s.downcase, "#e8e8e8"))
        when "jira" then jira(value)
        when "emoticon" then str(value.char)
        when "children", "pagetree" then ""
        end
      end

      def jira(key)
        url = JiraSettings.link_for(key)
        url ? "#link(#{lit(url)})[#{str(key)}]" : "#raw(#{lit(key)})"
      end
    end
  end
end
