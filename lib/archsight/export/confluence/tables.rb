# frozen_string_literal: true

require "erb"
require "kramdown"
require "kramdown-parser-gfm"
require_relative "../../view_table"
require_relative "../../helpers/macros"
require_relative "diagram_links"

module Archsight
  module Export
    module Confluence
      # A ViewTable::Table (the result of a view or of the requirements of some resources) as a regular table in
      # storage format. Views and requirements are live in Archsight; in Confluence they are the data of the moment
      # of the export.
      module Tables
        # status of a requirement -> colour of the Confluence status macro (as the web UI colours them)
        STATUS_COLOURS = { "implemented" => "green", "partial" => "yellow", "planned" => "blue" }.freeze

        # priority of a requirement -> colour of the Confluence status macro
        PRIORITY_COLOURS = { "must" => "red", "should" => "yellow", "may" => "grey" }.freeze

        module_function

        # @param empty [String] shown instead of the table when there are no rows
        # @return [String] block XML
        def xml(table, empty: "No resources found")
          out = +""
          out << %(<p><strong>#{h(table.title)}</strong> (#{table.total} #{table.total == 1 ? "item" : "items"})</p>\n) unless table.title.to_s.empty?
          if table.rows.empty?
            out << %(<p><em>#{h(empty)}</em></p>\n)
          else
            out << "<table><tbody>\n#{row(table.columns.map { |c| "<th>#{h(c)}</th>" })}"
            table.rows.each { |cells| out << row(cells.map { |cell| "<td>#{cell_xml(cell)}</td>" }) }
            out << "</tbody></table>\n"
          end
          out << %(<p><em>#{table.cut} more #{table.cut == 1 ? "row" : "rows"} not shown, see Archsight</em></p>\n) if table.cut.positive?
          out
        end

        def row(cells) = "<tr>#{cells.join}</tr>\n"

        def cell_xml(cell)
          return cell.resources.map { |resource| resource_xml(resource) }.join("<br />") unless cell.resources.empty?

          case cell.as
          when :status then lozenge(cell.text, STATUS_COLOURS)
          when :priority then cell.text.empty? ? "" : lozenge(cell.text, PRIORITY_COLOURS)
          when :markdown then markdown_xml(cell.text)
          else h(cell.text).gsub("\n", "<br />")
          end
        end

        # A link where the resource has a page in Confluence, else its name
        def resource_xml(resource)
          url = DiagramLinks.confluence_url(resource)
          url ? %(<a href="#{h(url)}">#{h(resource.name)}</a>) : h(resource.name)
        end

        def lozenge(text, colours)
          Helpers::Macros::Status.confluence(Helpers::Macros::Status::Value.new(colours.fetch(text, "grey"), text))
        end

        # Inline markdown (a requirement's story): the HTML of kramdown without the paragraph around a single line.
        # Raw HTML in the text is shown as text (it would not be well-formed storage XML); `<https://..>` links stay.
        def markdown_xml(text)
          return "" if text.to_s.strip.empty?

          safe = text.gsub(%r{<(?!(?:https?://|mailto:))}, "&lt;")
          html = Kramdown::Document.new(safe, input: "GFM", entity_output: :as_char, auto_ids: false).to_html.strip
          html.match(%r{\A<p>((?:(?!</?p>).)*)</p>\z}m) ? Regexp.last_match(1) : html
        end

        def h(text) = ERB::Util.html_escape(text)
      end
    end
  end
end
