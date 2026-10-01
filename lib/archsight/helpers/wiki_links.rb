# frozen_string_literal: true

require "erb"

module Archsight
  module Helpers
    # Replaces `[[Target]]`, `[[Target|label]]` and `[[Kind/Target]]` in rendered HTML with links.
    #
    # A target is looked up as (in order): `Kind/Name`, a page name, a page title, a resource name
    # across all kinds and finally as a substring of a resource name. Unknown or ambiguous targets
    # render as a `broken-link` span.
    class WikiLinks
      PATTERN = /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/

      def initialize(database, resolver: ResourceResolver.new(database))
        @database = database
        @resolver = resolver
      end

      CODE = %r{(<pre\b.*?</pre>|<code\b.*?</code>)}m

      # Code is shown as written, and `![[...]]` is an embed (see Embeds), not a link
      def render(html)
        html.split(CODE).each_with_index.map { |part, index| index.odd? ? part : render_links(part) }.join
      end

      # @return [String, Symbol] link path, or :missing / :ambiguous
      def resolve(target)
        return @resolver.call(target) if target.include?("/")

        page = find_page(target)
        return page_path(page) if page

        result = @resolver.call(target)
        return result unless result == :missing

        partial = find_partial(target)
        partial ? kind_path(*partial) : :missing
      end

      # Page path for a page name, nil if there is no such page
      def page_path(page)
        "/pages/#{ERB::Util.url_encode(page.name)}"
      end

      private

      def render_links(html)
        html.gsub(/(?<!!)#{PATTERN.source}/) do
          target = ::Regexp.last_match(1).strip
          explicit_label = ::Regexp.last_match(2)&.strip
          href = resolve(target)
          label = explicit_label || default_label(target)
          text = ERB::Util.html_escape(label)
          if href.is_a?(String)
            %(<a href="#{ERB::Util.html_escape(href)}">#{text}</a>)
          else
            %(<span class="broken-link" title="#{href == :ambiguous ? "Ambiguous reference" : "Resource not found"}">#{text}</span>)
          end
        end
      end

      # Pages are shown by title, everything else by the text as written
      def default_label(target)
        find_page(target)&.title || target
      end

      def find_page(target)
        pages = @database.instances_by_kind("Page")
        pages[target] || pages.values.find { |p| p.title.to_s.casecmp?(target) }
      end

      def find_partial(target)
        @database.instances.each do |klass, by_name|
          name = by_name.keys.sort.find { |n| n.include?(target) }
          return [klass.to_s.split("::").last, name] if name
        end
        nil
      end

      def kind_path(kind, name)
        "/kinds/#{kind}/instances/#{ERB::Util.url_encode(name).gsub("%3A", ":")}"
      end
    end
  end
end
