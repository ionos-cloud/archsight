# frozen_string_literal: true

require "open3"
require "digest"
require_relative "../renderer"
require_relative "../graph"
require_relative "../user_config"
require_relative "../resources"

module Archsight
  module Pdf
    # The dependency graph of a resource as an SVG document, the picture the resource's page shows: the resources its
    # relations lead to, as far as the page opens it (two steps, the layer of the resource and the one below it). The
    # page draws it in the browser; here it is drawn by the `dot` command of Graphviz (`pdf.dot` /
    # `ARCHSIGHT_PDF_DOT`, else `dot` from the PATH). A resource without relations has no graph, and without `dot`
    # there is none either, which is not an error: the document is made without it.
    class DependencyGraph
      include Archsight::GraphvisRenderer

      DEPTH = 2
      BOX = [500.0, 480.0].freeze # points: the text width of a page and the height a graph may take (to choose the direction)
      DIRECTIONS = %w[LR TB].freeze # left to right as on the page, or top to bottom
      TIMEOUT = 30
      CACHE_ENTRIES = 32

      # The colours of the layers (the page colours its nodes with the same, by CSS)
      LAYER_COLOURS = {
        "strategy" => "#F4A261", "business" => "#F9DC5C", "application" => "#6CBEED", "technology" => "#8AC926",
        "implementation" => "#F48FB1", "motivation" => "#CE93D8", "other" => "#cccccc"
      }.freeze
      # For the SVG, where the colours come as CSS: the page's style, without the borders of the label tables
      STYLE = "<style>\n#{LAYER_COLOURS.map { |layer, hex| ".layer-#{layer} path[fill=\"lightgrey\"] { fill: #{hex}; stroke: #{hex}; }" }.join("\n")}\n" \
              ".node polygon[fill=\"none\"] { stroke: none; }\n.node text { fill: #000000; }\n</style>\n".freeze
      LAYER_CLASS = /("class" = "[^"]*\blayer-(\w+)[^"]*")/

      @cache = {}
      @lock = Mutex.new

      class << self
        # Colours the nodes by layer, as the page does (the DOT has no colours, they come from the page's CSS)
        # @return [String] the SVG with a style element after its opening tag
        def colour_layers(svg)
          svg.sub(/(<svg\b[^>]*>)/) { "#{Regexp.last_match(1)}\n#{STYLE}" }
        end

        # The DOT of the page with what the page's CSS adds: the fill of a node by its layer, and label tables without borders
        def paint(dot)
          dot.gsub(LAYER_CLASS) do
            hex = LAYER_COLOURS.fetch(Regexp.last_match(2), LAYER_COLOURS["other"])
            "#{Regexp.last_match(1)} \"fillcolor\" = \"#{hex}\" \"color\" = \"#{hex}\""
          end.gsub("<TABLE>", '<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0">')
        end

        def cached(key)
          @lock.synchronize { @cache[key] } || yield.tap do |value|
            @lock.synchronize do
              @cache[key] = value
              @cache.shift while @cache.size > CACHE_ENTRIES
            end
          end
        end
      end

      # @param layers [Array<String>, nil] the layers to follow; the page's default for the resource's layer if nil
      def initialize(database, resource, depth: DEPTH, layers: nil, binary: nil)
        @database = database
        @resource = resource
        @depth = depth
        @layers = layers || Archsight::GraphvisRenderer.default_graph_layers(resource.class.layer)
        @binary = binary || UserConfig.setting("pdf", "dot") || "dot"
      end

      # @return [Boolean] whether the graph would show more than the resource itself
      def relations?
        !graph_targets(@resource, @layers).empty?
      end

      # @return [String, nil] the graph as a PDF page (drawn by `dot` itself, with the fonts it measured the text with), nil
      #   if there is nothing to draw or `dot` is not installed or fails
      def pdf = draw("pdf")

      # @return [String, nil] the graph as SVG, coloured by CSS; nil as for #pdf
      def svg
        out = draw("svg")
        out && self.class.colour_layers(out.dup.force_encoding(Encoding::UTF_8))
      end

      private

      def draw(format)
        return nil unless relations?

        dot = self.class.paint(create_graph_one(@database, @resource.klass, @resource.name, max_depth: @depth, layers: @layers))
        self.class.cached(Digest::SHA256.hexdigest("#{@binary}\0#{format}\0#{dot}")) { run(format, oriented(dot)) }
      end

      # The direction in which the graph is largest on the page: wide graphs read best left to right, tall ones top to
      # bottom. Left to right (the page's) wins unless the other is clearly better.
      def oriented(dot)
        DIRECTIONS.each_with_index.map { |direction, index| [with_direction(dot, direction), index.zero? ? 1.05 : 1.0] }
                                  .max_by { |candidate, bonus| fit(candidate) * bonus }.first
      end

      def with_direction(dot, direction)
        dot.sub(/"rankdir" = "?\w+"?/, "\"rankdir\" = \"#{direction}\"")
      end

      # How much of its natural size the graph keeps when it is made to fit the box (1.0: nothing lost); 0 if `dot` fails
      def fit(dot)
        out, status = Open3.capture2(@binary, "-Tplain", stdin_data: dot)
        return 0 unless status.success?

        _graph, _scale, width, height = out.lines.first.split
        [BOX[0] / (width.to_f * 72), BOX[1] / (height.to_f * 72), 1.0].min
      rescue Errno::ENOENT
        0
      end

      def run(format, dot)
        out, status = Open3.capture2(@binary, "-T#{format}", stdin_data: dot, binmode: true)
        status.success? && !out.empty? ? out : nil
      rescue Errno::ENOENT
        nil
      end
    end
  end
end
