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
      HOVER_LENGTH = 200

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

      # The page a `[[Target]]` names (by name or title), nil if there is none
      def page_for(target)
        find_page(target)
      end

      # The text of a link without an explicit label: a page by its title, a resource named `Kind/Name` by its name
      # (the kind is in the hover text), anything else as written (so a broken reference shows what must be fixed)
      def label_for(target)
        page = find_page(target)
        return page.title if page

        found = target.include?("/") ? @resolver.find(target) : nil
        found.is_a?(Array) ? found.last : target
      end

      # The page or resource a target names, nil if it names none or is ambiguous
      def target_for(target)
        page = find_page(target)
        return page if page

        found = @resolver.find(target)
        found = find_partial(target) || found if found == :missing && !target.include?("/")
        found.is_a?(Array) ? @database.instances_by_kind(found.first)[found.last] : nil
      end

      # Like target_for, but only an exact name counts: a page by name or title, `Kind/Name`, or a resource name that
      # exists in one kind. A target that only matches part of a name does not name anything. For relations that are
      # derived from text, where a wrong guess would be a wrong relation.
      def exact_target_for(target)
        page = find_page(target)
        return page if page

        found = @resolver.find(target)
        found.is_a?(Array) ? @database.instances_by_kind(found.first)[found.last] : nil
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
          label = explicit_label || label_for(target)
          text = ERB::Util.html_escape(label)
          if href.is_a?(String)
            %(<a href="#{ERB::Util.html_escape(href)}"#{hover(target_for(target))}>#{text}</a>)
          else
            %(<span class="broken-link" title="#{href == :ambiguous ? "Ambiguous reference" : "Resource not found"}">#{text}</span>)
          end
        end
      end

      # `title` attribute of a link: the kind and the first line of the description (the status of a page)
      def hover(instance)
        return "" unless instance

        kind = instance.class.name.split("::").last
        detail = kind == "Page" ? instance.annotations["page/status"] : plain_line(instance.annotations["architecture/description"])
        text = [kind, detail].map(&:to_s).reject(&:empty?).join("\n")
        %( title="#{ERB::Util.html_escape(text)}")
      end

      # The first line of a markdown text as plain text, at most HOVER_LENGTH characters
      def plain_line(markdown)
        line = markdown.to_s.lines.map(&:strip).find { |l| !l.empty? }.to_s
        line = line.gsub(%r{!?\[\[([^\]|]+/)?([^\]|]+)(?:\|([^\]]+))?\]\]}) { Regexp.last_match(3) || Regexp.last_match(2) }
                   .gsub(/!?\[([^\]]*)\]\([^)]*\)/, '\1').gsub(/\A[#>*\-\s]+/, "").delete("`*_")
        line.length > HOVER_LENGTH ? "#{line[0, HOVER_LENGTH - 1].rstrip}…" : line
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
