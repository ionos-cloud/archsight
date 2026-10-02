# frozen_string_literal: true

require "erb"
require_relative "../../helpers/macros"

module Archsight
  module Export
    module Confluence
      # The frontmatter of a page as the Page Properties (`details`) macro of Confluence: a two column table
      # with the status, owner, author, teams, tags and every further property. It is the counterpart of what the
      # import lifts out of such a table, and keeps Confluence's property reports working. People are written as
      # text (a name), not as user links.
      module PageProperties
        STATUS_COLOURS = {
          "wip" => "yellow", "draft" => "yellow", "rfc" => "blue", "review" => "blue", "proposed" => "blue",
          "approved" => "green", "accepted" => "green", "done" => "green", "final" => "green", "ga" => "green",
          "deprecated" => "red", "rejected" => "red", "obsolete" => "red", "superseded" => "grey"
        }.freeze
        TEAM_PREFIX = "Team:"
        URL = %r{https?://[^\s<>"]+}

        module_function

        # @param page [Archsight::Resources::Page]
        # @return [String] storage format, "" if the page has no properties
        def xml(page)
          rows = rows(page)
          return "" if rows.empty?

          body = rows.map { |label, value| "<tr><th>#{h(label)}</th><td>#{value}</td></tr>" }.join
          %(<ac:structured-macro ac:name="details"><ac:rich-text-body><table><tbody>#{body}</tbody></table></ac:rich-text-body></ac:structured-macro>\n)
        end

        # @return [Array<Array(String, String)>] label and the storage XML of the value
        def rows(page)
          annotations = page.annotations
          tags = annotations["page/tags"].to_s.split(",").map(&:strip).reject(&:empty?)
          teams, other = tags.partition { |tag| tag.start_with?(TEAM_PREFIX) }
          rows = [["Document status", status(annotations["page/status"])],
                  ["Document owner", text(person(annotations["page/owner"]))],
                  ["Document author", text(person(annotations["page/author"]))],
                  ["Teams", text(teams.map { |t| t.delete_prefix(TEAM_PREFIX).strip }.join(", "))],
                  ["Tags", text(other.join(", "))]]
          rows += page.properties.map { |key, value| [key, text(value)] }
          rows.reject { |_, value| value.empty? }
        end

        def status(value)
          title = value.to_s.strip
          return "" if title.empty?

          colour = STATUS_COLOURS.fetch(title.downcase, "grey")
          value = Helpers::Macros::Status.parse("#{colour} #{title}")
          value ? Helpers::Macros::Status.confluence(value) : h(title)
        end

        def person(value)
          Annotations::EmailRecipient.parse(value)&.fetch(:name)
        end

        # Text with its links and `{macros}` (jira, status, emoticon) made live, the rest escaped
        def text(value)
          source = value.to_s
          return "" if source.strip.empty?

          kept = []
          pattern = /#{Helpers::Macros::PATTERN.source}|#{URL.source}/
          marked = source.gsub(pattern) do |match|
            kept << live(match)
            "\u0000#{kept.length - 1}\u0000"
          end
          h(marked).gsub(/\u0000(\d+)\u0000/) { kept.fetch(Regexp.last_match(1).to_i) }
        end

        def live(match)
          return %(<a href="#{h(match)}">#{h(match)}</a>) if match.start_with?("http")

          name = match[/\A\{([a-z][a-z0-9-]*):/, 1]
          macro = Helpers::Macros.handler(name)
          value = macro&.parse(match[/\A\{[^:]+:(.*)\}\z/m, 1])
          value.nil? ? h(match) : macro.confluence(value)
        end

        def h(text) = ERB::Util.html_escape(text)
      end
    end
  end
end
