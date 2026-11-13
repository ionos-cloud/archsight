# frozen_string_literal: true

require "did_you_mean"
require_relative "../errors"
require_relative "../style/tints"
require_relative "../style/relations"
require_relative "../style/representers"
require_relative "../support/markdown_text"
require_relative "../support/text_metrics"

module Archsight
  module Diagram
    class Graph
      # What every `key "value"` attribute may be, per kind of thing it sits
      # on. The parser keeps attributes as a free-form hash, and every reader
      # silently falls back to a default for a key it doesn't know or a value
      # it can't use (`shape` on an edge, `style "orthorgonal"`, an unknown
      # `tint`...), so a typo would otherwise draw *something* and go
      # unnoticed. Everything is checked here, once the graph is built, and
      # reported with the owning block's/edge's line.
      #
      # An attribute the code never reads for that kind is an error too, not
      # just a misspelled one: `gap` on a leaf is as inert as `gapp` on a
      # container. Keep these tables in step with the readers in
      # `Graph::Node`/`Graph::Edge`/`Graph::DataFlow` and with `docs/diagram.md`.
      module Attributes
        NODE = %w[label tint link resource extend badge align legend].freeze
        LEAF_KINDS = %i[component application api database queue actor file text].freeze
        # `anchor` places a leaf that keeps its own size (`extend "false"`) inside a wider stack.
        LEAF = (NODE + %w[shape anchor]).freeze
        # A `text` has no box to restyle (no `shape`), but may wrap at `width` characters.
        TEXT = (NODE + %w[width]).freeze
        WIDTH_FORMAT = /\A[1-9]\d*\z/
        CONTAINER = (NODE + %w[gap padding ranks columns anchor]).freeze
        EDGE = %w[label style relation tint line].freeze
        DATAFLOW = %w[label color].freeze
        PORT = %w[label side at badge link resource].freeze
        BADGE_DEFINITION = %w[label tint].freeze
        LINE_DEFINITION = %w[label].freeze

        LINE_STYLES = %w[solid dashed dotted].freeze
        PORT_SIDES = %w[top bottom left right].freeze
        # A named spot on the port's side, or a percentage of its length (from the left or top).
        PORT_AT = /\A(left|center|right|top|bottom|(100|[1-9]?\d)(\.\d+)?%)\z/
        PORT_SHAPES = %w[rectangle file module].freeze

        EDGE_STYLES = %w[straight orthogonal].freeze
        LEAF_EXTEND = %w[true false].freeze
        CONTAINER_EXTEND = %w[true false height width].freeze
        ANCHORS = %w[top bottom left right center].freeze

        # `40` (pixels), `150%` (of the default), `+20%`/`-50%` (relative);
        # see `GapSpec`.
        GAP_FORMAT = /\A(\d+(\.\d+)?%?|[+-]\d+(\.\d+)?%)\z/
        COLOR_FORMAT = /\A#(\h{3}|\h{4}|\h{6}|\h{8})\z/
        LINK_SCHEMES = %w[http https mailto].freeze
        # `Name` or `Kind/Name`; resource names contain `:` but never `/` or whitespace
        RESOURCE_FORMAT = %r{\A([A-Za-z][A-Za-z0-9]*/)?[^/[:space:][:cntrl:]]+\z}

        module_function

        def check_node!(block, ranks_modes:)
          allowed = if block.kind == :text
                      TEXT
                    else
                      leaf?(block) ? LEAF : CONTAINER
                    end
          where = "#{block.kind} #{block.anonymous ? "(anonymous)" : block.id.inspect}"
          block.attrs.each do |key, value|
            check_name!(key, allowed, where, block.line)
            check_node_value!(key, value, block, where, ranks_modes)
          end
        end

        def check_edge!(ast_edge)
          where = "edge #{ast_edge.from} #{arrow(ast_edge.direction)} #{ast_edge.to}"
          raise GraphError, "#{where} (line #{ast_edge.line}) connects a node to itself, which has no line to draw" if ast_edge.from == ast_edge.to

          ast_edge.attrs.each do |key, value|
            check_name!(key, EDGE, where, ast_edge.line)
            case key
            when "label" then check_label!(value, where, ast_edge.line)
            when "style" then check_value!(key, value, EDGE_STYLES, where, ast_edge.line)
            when "relation" then check_value!(key, value, Relations.names, where, ast_edge.line)
            when "tint" then check_value!(key, value, Tints.names, where, ast_edge.line)
            when "line" then check_value!(key, value, LINE_STYLES, where, ast_edge.line)
            end
          end
        end

        # A port's attrs, and that its leaf has a box shape to put a tab on.
        def check_port!(ast_port, node)
          where = "port #{ast_port.id.inspect} of #{node.kind} #{node.id.inspect}"
          unless node.leaf? && node.kind != :text && PORT_SHAPES.include?(node.shape)
            raise GraphError, "#{where} (line #{ast_port.line}): ports need a box-shaped leaf (shape #{PORT_SHAPES.join(", ")}), " \
                              "not #{node.kind == :text ? "a text" : "shape #{node.shape.inspect}"}"
          end

          ast_port.attrs.each do |key, value|
            check_name!(key, PORT, where, ast_port.line)
            case key
            when "label" then check_label!(value, where, ast_port.line)
            when "side" then check_value!(key, value, PORT_SIDES, where, ast_port.line)
            when "at" then check_port_at!(value, ast_port.attrs["side"], where, ast_port.line)
            when "link" then check_link!(value, where, ast_port.line)
            when "resource" then check_resource!(value, ast_port.attrs, where, ast_port.line)
            end
          end
        end

        def check_port_at!(value, side, where, line)
          check_format!("at", value, PORT_AT, "left, center, right, top, bottom or a percentage (25%)", where, line)
          along = side.nil? || %w[top bottom].include?(side) ? %w[left right] : %w[top bottom]
          return unless (%w[left right top bottom] - along).include?(value)

          raise GraphError, "at #{value.inspect} on #{where} (line #{line}) does not lie along its #{side || "top"} side; expected #{along.join(", ")}, center or a percentage"
        end

        # A top-level `badge`/`line` definition.
        def check_definition!(definition)
          where = "#{definition.kind} #{definition.id.inspect}"
          allowed = definition.kind == :badge ? BADGE_DEFINITION : LINE_DEFINITION
          if definition.kind == :line && !(LINE_STYLES - ["solid"]).include?(definition.id)
            raise GraphError, "unknown line style #{definition.id.inspect} (line #{definition.line}); expected dashed or dotted" \
                              "#{suggestion(definition.id, LINE_STYLES - ["solid"])}"
          end

          definition.attrs.each do |key, value|
            check_name!(key, allowed, where, definition.line)
            check_label!(value, where, definition.line) if key == "label"
            check_value!(key, value, Tints.names, where, definition.line) if key == "tint"
          end
        end

        # A dataflow's own attrs and each of its branches'.
        def check_dataflow!(ast_dataflow)
          where = "dataflow #{ast_dataflow.id.inspect}"
          check_dataflow_attrs!(ast_dataflow.attrs, where, ast_dataflow.line)
          ast_dataflow.hops.each_cons(2) do |from, to|
            next unless from.is_a?(String) && from == to

            raise GraphError, "#{where} (line #{ast_dataflow.line}) hops from #{from.inspect} to itself, which has no line to draw"
          end
          ast_dataflow.hops.each do |hop|
            next unless hop.respond_to?(:branches)

            hop.branches.each { |b| check_dataflow_attrs!(b.attrs, "a branch of #{where}", b.line || ast_dataflow.line) }
          end
        end

        def check_dataflow_attrs!(attrs, where, line)
          attrs.each do |key, value|
            check_name!(key, DATAFLOW, where, line)
            check_color!(value, where, line) if key == "color"
            check_label!(value, where, line) if key == "label"
          end
        end

        def leaf?(block)
          LEAF_KINDS.include?(block.kind)
        end

        def arrow(direction)
          { directed: "->", bidirectional: "<->", undirected: "--" }.fetch(direction, "->")
        end

        def check_name!(key, allowed, where, line)
          return if allowed.include?(key)

          raise GraphError, "unknown attribute #{key.inspect} on #{where} (line #{line}); " \
                            "expected one of #{allowed.join(", ")}#{suggestion(key, allowed)}"
        end

        def check_node_value!(key, value, block, where, ranks_modes)
          line = block.line
          case key
          when "label", "legend" then check_label!(value, where, line)
          when "shape" then check_value!(key, value, Representers.names, where, line)
          when "tint" then check_value!(key, value, Tints.names, where, line)
          when "ranks" then check_value!(key, value, ranks_modes, where, line)
          when "extend" then check_value!(key, value, leaf?(block) ? LEAF_EXTEND : CONTAINER_EXTEND, where, line)
          when "anchor" then check_value!(key, value, ANCHORS, where, line)
          when "gap", "padding" then check_format!(key, value, GAP_FORMAT, "a pixel count (40), a percentage (150%) or a signed one (+20%, -50%)", where, line)
          when "width" then check_format!(key, value, WIDTH_FORMAT, "a positive number of characters per line", where, line)
          when "link" then check_link!(value, where, line)
          when "resource" then check_resource!(value, block.attrs, where, line)
          end
        end

        def check_value!(key, value, allowed, where, line)
          return if allowed.include?(value)

          raise GraphError, "unknown #{key} #{value.inspect} on #{where} (line #{line}); " \
                            "expected one of #{allowed.join(", ")}#{suggestion(value, allowed)}"
        end

        def check_format!(key, value, format, description, where, line)
          return if format.match?(value)

          raise GraphError, "invalid #{key} #{value.inspect} on #{where} (line #{line}); expected #{description}"
        end

        # The value ends up unescaped in the SVG's `<style>` block (a
        # dataflow's line color), so nothing but a hex color is allowed.
        def check_color!(value, where, line)
          check_format!("color", value, COLOR_FORMAT, "a hex color such as \"#1a56db\"", where, line)
        end

        # A label may hold `[text](url)` links, which are written into an
        # `href` just like the `link` attribute (found with the same
        # scanner the renderer uses, so the two never disagree).
        def check_label!(value, where, line)
          TextMetrics.markdown_runs(value).filter_map { |run| run.last[:link] }.each { |link| check_link!(link, where, line) }
        end

        # Written into an `href`: only web/mail links or relative ones, and
        # no whitespace or control characters (browsers ignore those inside
        # a scheme, which would let `java\tscript:` through a naive check).
        def check_link!(value, where, line)
          scheme = value[/\A([A-Za-z][A-Za-z0-9+.-]*):/, 1]
          return unless value.match?(/[[:space:][:cntrl:]]/) || (scheme && !LINK_SCHEMES.include?(scheme.downcase))

          raise GraphError, "invalid link #{value.inspect} on #{where} (line #{line}); expected an " \
                            "#{LINK_SCHEMES.join("/")} URL or a relative one, without whitespace"
        end

        # Resolved against the resource database when rendering (see
        # `ResourceLinks`), which turns it into the node's/port's `link`, so it
        # can't share one with an explicit one.
        def check_resource!(value, attrs, where, line)
          check_format!("resource", value, RESOURCE_FORMAT, "a resource name (Archsight:Web) or Kind/Name (ApplicationService/Archsight:Web)", where, line)
          return unless attrs.key?("link")

          raise GraphError, "#{where} (line #{line}) has both `link` and `resource`; a resource reference already provides the link"
        end

        def suggestion(given, allowed)
          guess = DidYouMean::SpellChecker.new(dictionary: allowed).correct(given).first
          guess ? " -- did you mean #{guess.inspect}?" : ""
        end
      end
    end
  end
end
