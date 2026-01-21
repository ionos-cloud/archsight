# frozen_string_literal: true

require "rack/utils"

module Archsight
  module Helpers
    # AnalysisRenderer provides HTML rendering for analysis result sections
    module AnalysisRenderer
      module_function

      # HTML escape helper
      def escape_html(text)
        Rack::Utils.escape_html(text.to_s)
      end

      # Render a single analysis section to HTML
      # @param section [Hash] Section data with :type and content
      # @param markdown_renderer [Proc, nil] Optional proc to render markdown
      def render_analysis_section(section, markdown_renderer: nil)
        case section[:type]
        when :heading
          render_heading(section)
        when :text
          render_text(section, markdown_renderer)
        when :message
          render_message(section)
        when :table
          render_table(section)
        when :list
          render_list(section)
        when :code
          render_code(section)
        else
          ""
        end
      end

      # Render analysis table section to HTML
      def render_analysis_table(section)
        render_table(section)
      end

      # Private rendering methods

      def render_heading(section)
        %(<div class="analysis-heading level-#{section[:level]}">#{escape_html(section[:text])}</div>)
      end

      def render_text(section, markdown_renderer)
        content = markdown_renderer ? markdown_renderer.call(section[:content]) : escape_html(section[:content])
        %(<div class="analysis-text">#{content}</div>)
      end

      def render_message(section)
        icon = case section[:level]
               when :error then "xmark-circle"
               when :warning then "warning-triangle"
               else "info-circle"
               end
        %(<div class="analysis-message message-#{section[:level]}"><i class="iconoir-#{icon}"></i> #{escape_html(section[:message])}</div>)
      end

      def render_table(section)
        headers = section[:headers].map { |h| "<th>#{escape_html(h)}</th>" }.join
        rows = section[:rows].map do |row|
          cells = row.map { |cell| "<td>#{escape_html(cell.to_s)}</td>" }.join
          "<tr>#{cells}</tr>"
        end.join
        %(<div class="analysis-table-wrapper"><table><thead><tr>#{headers}</tr></thead><tbody>#{rows}</tbody></table></div>)
      end

      def render_list(section)
        items = section[:items].map { |item| "<li>#{escape_html(item)}</li>" }.join
        %(<ul class="analysis-list">#{items}</ul>)
      end

      def render_code(section)
        lang_class = section[:lang] ? " class=\"language-#{section[:lang]}\"" : ""
        %(<pre class="code"><code#{lang_class}>#{escape_html(section[:content])}</code></pre>)
      end
    end
  end
end
