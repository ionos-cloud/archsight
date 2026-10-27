# frozen_string_literal: true

require "cgi"
require "digest"
require "rack/utils"

module Archsight
  module Helpers
    # Turns ```asd fenced blocks in rendered markdown into inline SVG diagrams.
    #
    # Two steps so the SVG stays out of the markdown post-processing (URL
    # auto-linking and `[[Name]]` links are plain-text passes over the whole
    # HTML and would rewrite labels and hrefs inside the SVG):
    #
    #   html, diagrams = DiagramBlocks.extract(html, resolver: resolver)   # blocks -> placeholders
    #   ...further processing of html...
    #   html = DiagramBlocks.restore(html, diagrams)   # placeholders -> SVG
    module DiagramBlocks
      BLOCK = %r{<pre><code class="language-asd">(.*?)</code></pre>}m
      CACHE_LIMIT = 256
      INCLUDE = /\binclude\s+"/

      @cache = {}
      @cache_lock = Mutex.new

      module_function

      # @return [Array(String, Hash{String => String})] HTML with a placeholder per
      #   asd block, and the rendered replacement for each placeholder
      def extract(html, resolver: nil, includes: nil)
        diagrams = {}
        replaced = html.gsub(BLOCK) do |block|
          placeholder = "<!--asd-diagram:#{diagrams.size}-->"
          diagrams[placeholder] = render_block(::CGI.unescapeHTML(Regexp.last_match(1)), block, resolver: resolver, includes: includes)
          placeholder
        end
        [replaced, diagrams]
      end

      def restore(html, diagrams)
        return html if diagrams.empty?

        html.gsub(/<!--asd-diagram:\d+-->/) { |placeholder| diagrams.fetch(placeholder, placeholder) }
      end

      # A whole diagram definition (the `architecture/diagram` annotation) as
      # inline SVG, or the error box plus the source if it doesn't render.
      def render_diagram(source, resolver: nil, includes: nil)
        escaped = ::Rack::Utils.escape_html(source)
        render_block(source, %(<pre><code class="language-asd">#{escaped}</code></pre>), resolver: resolver, includes: includes)
      end

      # A diagram for the editor preview: the same SVG (and cache) as a rendered page, but a diagram that
      # does not render answers with just the error message (it carries the line) instead of the error box
      # that repeats the source, which the editor already shows.
      #
      # @return [Hash] `{ html: "<figure ...>", error: nil }` or `{ html: nil, error: "message" }`
      def preview(source, resolver: nil, includes: nil)
        { html: render_svg(source, resolver: resolver, includes: includes), error: nil }
      rescue Archsight::Diagram::Error => e
        { html: nil, error: e.message }
      end

      # Source of every ```asd block in `markdown` (for the linter).
      def sources(markdown)
        markdown.scan(/^[ \t]*(?:```|~~~)asd[ \t]*\n(.*?)^[ \t]*(?:```|~~~)[ \t]*$/m).flatten
      end

      # The id prefix is derived from the source, so the same diagram always
      # renders to the same markup (cacheable), while different diagrams
      # sharing a page never share ids. Two identical diagrams on one page do
      # share ids, but they're identical, so nothing resolves to the wrong one.
      #
      # `resource "..."` references resolve against the database, which can
      # change under a cached render (a reload, an edit), so the outcome of
      # each reference is part of the key.
      def render_block(source, original, resolver: nil, includes: nil)
        render_svg(source, resolver: resolver, includes: includes)
      rescue Archsight::Diagram::Error => e
        message = ::Rack::Utils.escape_html(e.message)
        %(<div class="asd-diagram-error"><p><strong>Diagram error:</strong> #{message}</p>#{original}</div>)
      end

      # @raise [Archsight::Diagram::Error] if the source does not render
      def render_svg(source, resolver: nil, includes: nil)
        key = fingerprint(source, resolver: resolver, includes: includes)
        cached(key) do
          warnings = [] #: Array[String]
          svg = Archsight::Diagram.render(source, id_prefix: "asd#{key}", resolver: resolver, includes: includes, warnings: warnings)
          warnings.each { |message| warn "Diagram: #{message}" }
          %(<figure class="asd-diagram">#{svg.sub(/\A<\?xml[^>]*\?>\s*/, "")}</figure>)
        end
      end

      # The cache key of a diagram: its source plus how each `resource` reference resolves right now. It
      # changes exactly when the rendered diagram would, so it is also a good ETag. The diagrams it includes
      # are part of it: their sources, and how their `resource` references resolve.
      def fingerprint(source, resolver: nil, includes: nil)
        included = included_sources(source, includes)
        ::Digest::SHA256.hexdigest([source, included, resolutions([source, *included.values], resolver)].inspect)[0, 12]
      end

      # A diagram as a standalone SVG document (what the assets API serves for an .asd file), cached by
      # fingerprint like the inline diagrams.
      # @raise [Archsight::Diagram::Error] if the source does not render
      def standalone_svg(source, resolver: nil, includes: nil)
        key = fingerprint(source, resolver: resolver, includes: includes)
        cached("svg-#{key}") { Archsight::Diagram.render(source, id_prefix: "asd#{key}", resolver: resolver, includes: includes) }
      end

      # `{ path => source }` of the diagrams `source` includes, recursively; empty for a source that includes
      # none (checked on the text first: most diagrams include nothing and need not be parsed twice)
      # @raise [Archsight::Diagram::Error] if the source or an included one is not a valid diagram
      def included_sources(source, includes)
        return {} unless includes && source.match?(INCLUDE)

        Archsight::Diagram.expand(source, includes: includes).sources
      end

      def resolutions(sources, resolver)
        return [] unless resolver

        references = sources.flat_map { |source| source.scan(/\bresource\s+"([^"]*)"/).flatten }
        references.uniq.map { |reference| [reference, resolver.call(reference)] }
      end

      def cached(key)
        @cache_lock.synchronize { @cache[key] } || yield.tap do |svg|
          @cache_lock.synchronize do
            @cache.clear if @cache.size >= CACHE_LIMIT
            @cache[key] = svg
          end
        end
      end
    end
  end
end
