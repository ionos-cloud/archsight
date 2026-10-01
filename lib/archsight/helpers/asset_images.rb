# frozen_string_literal: true

require "cgi"
require "erb"
require "kramdown"
require "kramdown-parser-gfm"
require_relative "../assets"

module Archsight
  module Helpers
    # Makes the images of rendered markdown point at assets (see Archsight::Assets) and reports the ones
    # that cannot be served, for the linter.
    #
    # In the HTML of a markdown file (`base_dir` is the directory that file is in, relative to the
    # resources directory) every `<img src>` that is a relative reference becomes:
    # - an image served by the assets API, or for a .drawio file a placeholder the frontend turns into the viewer
    # - a visible `broken-asset` marker when the reference leaves the assets tree, does not exist or is a
    #   file type that is not served.
    # URLs (https:, data:, //host, /path) are left alone.
    module AssetImages
      IMG = /<img\b[^>]*>/i
      SRC = /\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)')/i
      ALT = /\balt\s*=\s*(?:"([^"]*)"|'([^']*)')/i

      REASONS = {
        outside: "the path leaves the resources directory",
        type: "this file type is not served",
        missing: "no such file"
      }.freeze

      module_function

      # @return [String] the HTML with its images rewritten
      def rewrite(html, base_dir:, resources_dir:)
        html.gsub(IMG) do |tag|
          reference = attribute(tag, SRC)
          next tag if reference.nil? || Assets.external?(reference)

          status, path = classify(reference, base_dir, resources_dir)
          alt = attribute(tag, ALT).to_s
          case status
          when :ok then Assets.drawio?(path) ? drawio(path, alt) : image(tag, path)
          else broken(reference, alt, status, path)
          end
        end
      end

      # Problems with the image references of a markdown text.
      # @return [Array<Hash>] `{ reference:, status: :outside|:type|:missing, path: }`
      def audit(markdown, base_dir:, resources_dir:)
        html = Kramdown::Document.new(markdown.to_s, input: "GFM").to_html
        html.scan(IMG).filter_map do |tag|
          reference = attribute(tag, SRC)
          next if reference.nil? || Assets.external?(reference)

          status, path = classify(reference, base_dir, resources_dir)
          { reference: reference, status: status, path: path } unless status == :ok
        end
      end

      # @return [Array(Symbol, String)] :ok, :outside, :type or :missing, and the normalized asset path (nil if :outside)
      def classify(reference, base_dir, resources_dir)
        path = Assets.resolve_reference(reference, base_dir)
        return [:outside, nil] unless path

        problem = Assets.problem(path, resources_dir: resources_dir)
        [problem || :ok, path]
      end

      # The unescaped value of an attribute (src, alt) of a tag, nil if it has none
      def attribute(tag, pattern)
        match = tag.match(pattern)
        match && CGI.unescapeHTML(match[1] || match[2])
      end

      def image(tag, path)
        rewritten = tag.sub(SRC) { %(src="#{h(Assets.url_for(path))}") }
        rewritten.match?(/\bloading\s*=/i) ? rewritten : rewritten.sub(%r{\s*/?>\z}, ' loading="lazy" />')
      end

      def drawio(path, alt)
        url = h(Assets.url_for(path))
        label = alt.empty? ? File.basename(path) : alt
        %(<span class="drawio-diagram" data-drawio-src="#{url}" data-drawio-title="#{h(alt)}"><a href="#{url}">#{h(label)}</a></span>)
      end

      def broken(reference, alt, status, path)
        detail = status == :missing ? "#{REASONS[:missing]}: #{path}" : REASONS.fetch(status)
        %(<span class="broken-asset" title="#{h("#{reference}: #{detail}")}">#{h(alt.empty? ? reference : alt)}</span>)
      end

      def h(text)
        ERB::Util.html_escape(text)
      end
    end
  end
end
