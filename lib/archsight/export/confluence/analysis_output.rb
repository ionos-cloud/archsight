# frozen_string_literal: true

require "erb"
require_relative "../../markdown"

module Archsight
  module Export
    module Confluence
      # The result of an analysis (`![[Analysis/Name]]` in a page, run at the export) in storage format: headings,
      # text, tables and lists as Confluence content, messages as info/note/warning panels, code as a code macro.
      # Like a view, it is the data of the moment of the export. The XML holds nothing that changes between two
      # runs on the same data (no time, no duration), so an unchanged result leaves the page unchanged.
      class AnalysisOutput
        # level of a message -> Confluence panel macro
        PANELS = { error: "warning", warning: "note", info: "info" }.freeze
        LINK = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/
        BREAK = %r{<br\s*/?>|\r?\n}i

        # @param link [Proc] (target, label) -> inline XML of a `[[...]]` link
        # @param code [Proc] (source, language) -> block XML of a code macro
        def initialize(link:, code:)
          @link = link
          @code = code
        end

        # @return [String] block XML
        def xml(name, result)
          out = %(<p><strong>#{h(name)}</strong> (result of the analysis at the export)</p>\n)
          return out << %(<p><em>The analysis failed: #{h(result.error)}</em></p>\n) unless result.success?

          result.sections.each { |section| out << section_xml(section).to_s }
          out
        end

        private

        def section_xml(section)
          case section[:type]
          when :heading then heading(section)
          when :text then block_markdown(section[:content])
          when :table then table(section)
          when :list then "<ul>#{section[:items].map { |item| "<li>#{inline(item)}</li>" }.join}</ul>\n"
          when :message then panel(section)
          when :code then @code.call(section[:content].to_s, section[:lang].to_s)
          end
        end

        # level 0 is a section of the analysis: below the page's own headings
        def heading(section)
          level = (section[:level].to_i + 3).clamp(3, 6)
          "<h#{level}>#{h(section[:text])}</h#{level}>\n"
        end

        def table(section)
          head = "<tr>#{section[:headers].map { |header| "<th>#{h(header)}</th>" }.join}</tr>\n"
          rows = section[:rows].map { |cells| "<tr>#{cells.map { |cell| "<td>#{inline(cell)}</td>" }.join}</tr>\n" }
          "<table><tbody>\n#{head}#{rows.join}</tbody></table>\n"
        end

        def panel(section)
          macro = PANELS.fetch(section[:level], "info")
          %(<ac:structured-macro ac:name="#{macro}"><ac:rich-text-body><p>#{inline(section[:message])}</p></ac:rich-text-body></ac:structured-macro>\n)
        end

        # A cell, list item or message: markdown and [[links]] inline, a `<br>` or newline breaks the line, other
        # HTML is text
        def inline(value)
          value.to_s.split(BREAK).map { |line| inline_markdown(line) }.join("<br />")
        end

        def inline_markdown(text)
          with_links(text) do |marked|
            html = markdown(marked)
            html.match(%r{\A<p>((?:(?!</?p>).)*)</p>\z}m) ? Regexp.last_match(1) : html
          end
        end

        def block_markdown(text) = "#{with_links(text.to_s) { |marked| markdown(marked) }}\n"

        # Keeps the [[links]] out of kramdown (it would split the brackets) and puts their XML into its result
        def with_links(text)
          links = []
          marked = text.gsub(LINK) { (links << [Regexp.last_match(1).strip, Regexp.last_match(2)&.strip]) && "ARCHSIGHTAL#{links.size - 1}X" }
          yield(marked).gsub(/ARCHSIGHTAL(\d+)X/) { @link.call(*links[Regexp.last_match(1).to_i]) }
        end

        # kramdown HTML of the text: raw HTML is shown as text (it would not be well-formed storage XML)
        def markdown(text)
          return "" if text.strip.empty?

          safe = text.gsub(%r{<(?!(?:https?://|mailto:))}, "&lt;")
          Archsight::Markdown.unwrapped(safe, entity_output: :as_char, auto_ids: false).to_html.strip
                             .gsub(%r{<(br|hr|img)([^>]*?)\s*/?>}, '<\1\2 />')
        end

        def h(text) = ERB::Util.html_escape(text)
      end
    end
  end
end
