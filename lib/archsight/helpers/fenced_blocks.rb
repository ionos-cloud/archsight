# frozen_string_literal: true

require "cgi"
require "erb"
require "yaml"

module Archsight
  module Helpers
    # What the ```lang blocks of rendered markdown that become something else (ViewBlocks, RequirementsBlocks) have
    # in common. Two steps, so what a block becomes stays out of the markdown post-processing (URL auto-linking,
    # macros and `[[Name]]` links are plain-text passes over the whole HTML):
    #
    #   html, blocks = FencedBlocks.extract(html, language: "view", prefix: "view-block") { |source, original| ... }
    #   ...further processing of html...
    #   html = FencedBlocks.restore(html, blocks, prefix: "view-block")
    module FencedBlocks
      module_function

      # @yield [source, original] the block's source and its `<pre><code>` HTML; returns the HTML to put in its place
      # @return [Array(String, Hash{String => String})] HTML with a placeholder per block, and the replacement for each
      def extract(html, language:, prefix:)
        blocks = {}
        pattern = %r{<pre><code class="language-#{Regexp.escape(language)}">(.*?)</code></pre>}m
        replaced = html.gsub(pattern) do |block|
          placeholder = "<!--#{prefix}:#{blocks.size}-->"
          blocks[placeholder] = yield(::CGI.unescapeHTML(Regexp.last_match(1)), block)
          placeholder
        end
        [replaced, blocks]
      end

      def restore(html, blocks, prefix:)
        return html if blocks.empty?

        html.gsub(/<!--#{Regexp.escape(prefix)}:\d+-->/) { |placeholder| blocks.fetch(placeholder, placeholder) }
      end

      # Source of every block of that language in `markdown` (for the linter).
      def sources(markdown, language:)
        markdown.scan(/^[ \t]*(?:```|~~~)#{Regexp.escape(language)}[ \t]*\n(.*?)^[ \t]*(?:```|~~~)[ \t]*$/m).flatten
      end

      # `<div class="css-class"><p><strong>Label:</strong> message</p>original</div>`
      def error_box(css_class, label, message, original)
        %(<div class="#{css_class}"><p><strong>#{label}:</strong> #{::ERB::Util.html_escape(message)}</p>#{original}</div>)
      end

      # `<div class="css-class" data-a="..." ...>original</div>`, the values escaped
      def placeholder(css_class, data, original)
        attributes = data.map { |name, value| %( data-#{name}="#{::ERB::Util.html_escape(value)}") }.join
        %(<div class="#{css_class}"#{attributes}>#{original}</div>)
      end

      # A YAML mapping, without aliases or arbitrary objects
      # @raise [Psych::Exception]
      def load_yaml(source)
        YAML.safe_load(source, aliases: false)
      end
    end
  end
end
