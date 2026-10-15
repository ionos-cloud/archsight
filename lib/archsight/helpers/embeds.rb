# frozen_string_literal: true

require "erb"

module Archsight
  module Helpers
    # Replaces `![[Kind/Name]]` in rendered HTML by a placeholder for the content of that resource: the result list of
    # a View, the result of an Analysis, the description of any other resource (a goal, a capability, ...). The
    # frontend turns each placeholder into that content (it loads and runs it itself, so rendering a page never
    # executes a query or a script):
    #
    #   <div class="kind-embed" data-kind="View" data-name="View:Services"><a href="/kinds/View/instances/...">...</a></div>
    #
    # The link inside is what API and MCP consumers (and a browser without script) get. A reference that does not
    # name an existing resource (or names a page) renders as a `broken-link` marker. Code (`<pre>`, `<code>`) is
    # left alone.
    class Embeds
      # Embeds with live content; every other kind shows its description
      LIVE_KINDS = %w[View Analysis].freeze
      # Pages and menus are not resources with a description
      NOT_EMBEDDABLE = %w[Page PageMenu].freeze
      PATTERN = /!\[\[([^\]|]+)\]\]/
      PARAGRAPH = %r{<p>\s*(#{PATTERN.source})\s*</p>}
      CODE = %r{(<pre\b.*?</pre>|<code\b.*?</code>)}m

      REASONS = {
        kind: "embed a resource as Kind/Name (a View, an Analysis or the description of any other resource); " \
              "pages cannot be embedded",
        missing: "no such resource",
        ambiguous: "ambiguous reference"
      }.freeze

      # Whether `![[kind/...]]` can be embedded: a known kind that is not a page
      def self.embeddable_kind?(kind)
        !Archsight::Resources[kind].nil? && !NOT_EMBEDDABLE.include?(Archsight::Resources.canonical(kind))
      end

      def initialize(database, resolver: ResourceResolver.new(database))
        @database = database
        @resolver = resolver
      end

      def render(html)
        html.split(CODE).each_with_index.map { |part, index| index.odd? ? part : render_text(part) }.join
      end

      # Problems with the embeds of a markdown text (for the linter).
      # @return [Array<Hash>] `{ reference:, problem: :kind|:missing|:ambiguous }`
      def audit(markdown)
        markdown.to_s.split(/^[ \t]*(?:```|~~~).*?^[ \t]*(?:```|~~~)[ \t]*$/m).flat_map do |text|
          text.gsub(/`[^`\n]*`/, "").scan(PATTERN).flatten.filter_map do |reference|
            problem = check(reference.strip).last
            { reference: reference.strip, problem: problem } if problem
          end
        end
      end

      private

      def render_text(text)
        text.gsub(PARAGRAPH) { embed(::Regexp.last_match(2), block: true) }
            .gsub(PATTERN) { embed(::Regexp.last_match(1), block: false) }
      end

      def embed(reference, block:)
        reference = reference.strip
        (kind, name), problem = check(reference)
        return broken(reference, problem) if problem

        href = ERB::Util.html_escape(@resolver.call(reference))
        link = %(<a href="#{href}">#{h(name)}</a>)
        return link unless block

        %(<div class="kind-embed" data-kind="#{h(kind)}" data-name="#{h(name)}">#{link}</div>)
      end

      # @return [Array(Array(String, String), Symbol)] kind and name, and the problem (nil if it is embeddable)
      def check(reference)
        kind, name = reference.split("/", 2)
        return [[kind, name], :kind] unless name && self.class.embeddable_kind?(kind)

        problem = @resolver.call(reference)
        [[kind, name], problem.is_a?(Symbol) ? problem : nil]
      end

      def broken(reference, problem)
        %(<span class="broken-link" title="#{h(REASONS.fetch(problem))}">#{h(reference)}</span>)
      end

      def h(text)
        ERB::Util.html_escape(text)
      end
    end
  end
end
