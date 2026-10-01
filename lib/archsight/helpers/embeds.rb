# frozen_string_literal: true

require "erb"

module Archsight
  module Helpers
    # Replaces `![[View/Name]]` and `![[Analysis/Name]]` in rendered HTML by a placeholder for the live content of
    # that view or analysis. The frontend turns each placeholder into the result list or the analysis result (it
    # loads and runs them itself, so rendering a page never executes a query or a script):
    #
    #   <div class="kind-embed" data-kind="View" data-name="View:Services"><a href="/kinds/View/instances/...">...</a></div>
    #
    # The link inside is what API and MCP consumers (and a browser without script) get. A reference that does not
    # name an existing View or Analysis renders as a `broken-link` marker. Code (`<pre>`, `<code>`) is left alone.
    class Embeds
      KINDS = %w[View Analysis].freeze
      PATTERN = /!\[\[([^\]|]+)\]\]/
      PARAGRAPH = %r{<p>\s*(#{PATTERN.source})\s*</p>}
      CODE = %r{(<pre\b.*?</pre>|<code\b.*?</code>)}m

      REASONS = {
        kind: "only #{KINDS.join(" and ")} can be embedded, written View/Name or Analysis/Name",
        missing: "no such resource",
        ambiguous: "ambiguous reference"
      }.freeze

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
        return [[kind, name], :kind] unless name && KINDS.include?(kind)

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
