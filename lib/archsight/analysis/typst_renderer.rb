# frozen_string_literal: true

require_relative "../markdown"
require_relative "../diagram"

module Archsight
  module Analysis
    # Renders analysis results as one Typst document (https://typst.app).
    #
    # All text is emitted as Typst string literals (`#"..."`) and structure as
    # function calls (`#strong[...]`), so no content can be mistaken for markup.
    class TypstRenderer
      ROW_LIMIT = 10
      HEADING_OFFSET = 2 # section level 0 becomes a level-2 heading, the analysis name is level 1
      LANGUAGE = /\A[A-Za-z0-9+#-]+\z/
      MESSAGE_FILL = { error: "rgb(\"#fde8e8\")", warning: "rgb(\"#fff3cc\")", info: "rgb(\"#ddeeff\")" }.freeze
      SYMBOLS = {
        ndash: "–", mdash: "—", hellip: "…", laquo: "«", raquo: "»", laquo_space: "« ", raquo_space: " »",
        lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”"
      }.freeze

      PREAMBLE = <<~TYPST
        #set document(title: "Archsight analysis")
        #set page(paper: "a4", margin: 2cm, numbering: "1")
        #set text(size: 10pt)
        #show raw.where(block: true): it => block(fill: luma(245), inset: 8pt, radius: 3pt, width: 100%, it)
      TYPST

      # @param results [Array<Archsight::Analysis::Result>]
      # @param verbose [Boolean] show every table row and list item and the error backtrace
      # @param template [String, nil] Typst file to import instead of the built-in layout. It must define
      #   `archsight-report` (a show rule for the document) and `analysis-result` (one call per analysis,
      #   with the data sections as a dictionary and the other sections as body).
      def initialize(results, verbose: false, template: nil)
        @results = results
        @verbose = verbose
        @template = template
      end

      # @return [String] Typst source
      def render
        return [template_preamble, *@results.map { |result| template_result(result) }].join("\n") if @template

        [PREAMBLE, title, summary, *@results.map { |result| render_result(result) }].join("\n")
      end

      private

      def title
        "#align(center)[#text(size: 20pt, weight: \"bold\")[#{str("Archsight analysis")}]]\n"
      end

      def summary
        completed = @results.count(&:success?)
        failed = @results.count(&:failed?)
        with_warnings = @results.count { |result| result.success? && result.warnings? }
        items = ["#{completed} completed"]
        items << "#{failed} failed" if failed.positive?
        items << "#{with_warnings} with warnings" if with_warnings.positive?
        "#list(#{items.map { |item| "[#{str(item)}]" }.join(", ")})\n"
      end

      def template_preamble
        counts = { count: @results.size, passed: @results.count(&:success?), failed: @results.count(&:failed?),
                   findings: @results.count(&:has_findings?) }
        "#import #{lit(@template)}: *\n#show: archsight-report.with(#{named_args(counts)})\n"
      end

      # One `analysis-result` call: metadata and data as named arguments, the rendered sections as body
      def template_result(result)
        data = result.sections.select { |s| s[:type] == :data }.to_h { |s| [s[:key], s[:value]] }
        body = []
        body << error_block(result) if result.failed?
        body.concat(result.sections.filter_map { |section| render_section(section) })
        args = { name: result.name, description: description(result), state: state(result),
                 duration: result.duration_str, data: data }
        "#analysis-result(#{named_args(args)})[\n#{body.join("\n\n")}\n]\n"
      end

      def description(result)
        analysis = result.analysis
        analysis.respond_to?(:annotations) ? analysis.annotations["analysis/description"] : nil
      end

      def state(result)
        return "failed" if result.failed?

        result.has_findings? ? "findings" : "passed"
      end

      def named_args(hash)
        hash.map { |key, value| "#{key}: #{typst_value(value)}" }.join(", ")
      end

      # A Ruby value as a Typst literal: Hash -> dictionary (string keys), Array -> array, nil -> none
      def typst_value(value)
        case value
        when Hash then value.empty? ? "(:)" : "(#{value.map { |k, v| "#{lit(k.to_s)}: #{typst_value(v)}" }.join(", ")})"
        when Array then "(#{value.map { |v| typst_value(v) }.join(", ")}#{"," if value.size == 1})"
        when Integer, true, false then value.to_s
        when Float then value.finite? ? value.to_s : "none"
        when nil then "none"
        else lit(value.to_s)
        end
      end

      def render_result(result)
        parts = ["#pagebreak(weak: true)", "#heading(level: 1)[#{str(result.name)}]"]
        status = result.failed? ? "failed" : "completed"
        status += ", #{result.duration_str}" unless result.duration_str.empty?
        parts << "#text(fill: gray)[#{str(status)}]"
        parts << error_block(result) if result.failed?
        parts.concat(result.sections.filter_map { |section| render_section(section) })
        "#{parts.join("\n\n")}\n"
      end

      def error_block(result)
        lines = [message_block(:error, "**Error:** #{result.error}")]
        lines << "#raw(#{lit(result.error_backtrace.join("\n"))}, block: true)" if @verbose && result.error_backtrace&.any?
        lines.join("\n\n")
      end

      def render_section(section)
        case section[:type]
        when :heading then "#heading(level: #{[section[:level] + HEADING_OFFSET, 6].min})[#{str(section[:text])}]"
        when :text then markdown(section[:content])
        when :table then table(section[:headers], section[:rows])
        when :list then list(section[:items])
        when :code then code(section)
        when :message then message_block(section[:level], section[:message])
        when :data then nil # only for templates, passed to analysis-result
        end
      end

      def message_block(level, text)
        fill = MESSAGE_FILL.fetch(level, MESSAGE_FILL[:info])
        "#block(fill: #{fill}, inset: 8pt, radius: 3pt, width: 100%)[#{markdown(text, inline: true)}]"
      end

      # A template produces a document to hand out, so it gets every row
      def full?
        @verbose || !@template.nil?
      end

      def table(headers, rows)
        shown = full? ? rows : rows.first(ROW_LIMIT)
        head = headers.map { |header| "[#strong[#{str(header)}]]" }
        cells = shown.flat_map { |row| headers.each_index.map { |i| "[#{str(row[i])}]" } }
        out = "#table(columns: #{headers.size}, inset: 5pt, stroke: 0.5pt + luma(200), " \
              "table.header(#{head.join(", ")}), #{cells.join(", ")})"
        out += "\n\n#emph[#{str("...and #{rows.size - ROW_LIMIT} more rows")}]" if shown.size < rows.size
        out
      end

      def list(items)
        shown = full? ? items : items.first(ROW_LIMIT)
        out = "#list(#{shown.map { |item| "[#{markdown(item, inline: true)}]" }.join(", ")})"
        out += "\n\n#emph[#{str("...and #{items.size - ROW_LIMIT} more items")}]" if shown.size < items.size
        out
      end

      def code(section)
        return diagram(section[:content]) if section[:lang].to_s == "asd"

        raw(section[:content], section[:lang])
      end

      def diagram(source)
        svg = Archsight::Diagram.render(source)
        "#image(bytes(#{lit(svg)}), format: \"svg\", width: 100%)"
      rescue Archsight::Diagram::Error => e
        [message_block(:error, "Diagram could not be rendered: #{e.message}"), raw(source, "asd")].join("\n\n")
      end

      def raw(source, lang)
        lang_arg = lang.to_s.match?(LANGUAGE) ? ", lang: #{lit(lang)}" : ""
        "#raw(#{lit(source.to_s.chomp)}, block: true#{lang_arg})"
      end

      # A Typst string literal, for use as a function argument
      def lit(text)
        escaped = text.to_s.delete("\r").gsub(/[\\"]/) { "\\#{Regexp.last_match(0)}" }.gsub("\n", "\\n")
        "\"#{escaped}\""
      end

      # A Typst string literal as markup, for use inside content
      def str(text)
        "##{lit(text)}"
      end

      # ---- markdown -> Typst

      def markdown(source, inline: false)
        root = Archsight::Markdown.document(source).root
        out = blocks(root.children)
        inline ? out.gsub(/\n\n+/, " #linebreak() ") : out
      end

      def blocks(elements)
        elements.filter_map { |node| block(node) }.join("\n\n")
      end

      def block(node)
        case node.type
        when :p then inlines(node.children)
        when :header then "#heading(level: #{[node.options[:level] + 1, 6].min})[#{inlines(node.children)}]"
        when :codeblock then raw(node.value, node.options[:lang])
        when :blockquote then "#quote(block: true)[#{blocks(node.children)}]"
        when :ul then "#list(#{node.children.map { |li| "[#{blocks(li.children)}]" }.join(", ")})"
        when :ol then "#enum(#{node.children.map { |li| "[#{blocks(li.children)}]" }.join(", ")})"
        when :hr then "#line(length: 100%)"
        when :table then markdown_table(node)
        when :blank, :html_element, :xml_comment then nil
        else inlines(node.children) unless node.children.empty?
        end
      end

      def markdown_table(node)
        rows = node.children.flat_map(&:children)
        cells = rows.map { |tr| tr.children.map { |td| "[#{inlines(td.children)}]" } }
        width = cells.map(&:size).max || 1
        "#table(columns: #{width}, inset: 5pt, stroke: 0.5pt + luma(200), #{cells.flatten.join(", ")})"
      end

      def inlines(elements)
        elements.map { |node| inline(node) }.join
      end

      def inline(node)
        case node.type
        when :text then str(node.value)
        when :em then "#emph[#{inlines(node.children)}]"
        when :strong then "#strong[#{inlines(node.children)}]"
        when :codespan then "#raw(#{lit(node.value)})"
        when :a then "#link(#{lit(node.attr["href"])})[#{inlines(node.children)}]"
        when :br then "#linebreak()"
        when :entity then str(node.value.char)
        when :smart_quote, :typographic_sym then str(SYMBOLS.fetch(node.value, node.value.to_s))
        when :html_element then inlines(node.children)
        else inlines(node.children)
        end
      end
    end
  end
end
