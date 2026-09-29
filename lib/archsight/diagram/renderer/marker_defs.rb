# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # `<marker>` def generation -- the legend-hover CSS that animates a
      # dataflow's line(s) when its legend row is hovered lives in
      # `Stylesheet` instead, so the document has exactly one `<style>` block,
      # not one per collaborator that happens to need some CSS; likewise
      # `markers_markup` is unwrapped (no `<defs>` of its own) so
      # `Renderer#render` can combine it with `ContainerEffects`'s own
      # gradients/filter into one shared `<defs>`, not a second one.
      class MarkerDefs
        # A relation marker's size scales with its path's `stroke-width`
        # (SVG's own default `markerUnits="strokeWidth"`) -- fine for a plain
        # edge, but a dataflow's marker must stay a fixed, tuned size
        # (`markerUnits="userSpaceOnUse"`) independent of `DATAFLOW_STROKE_WIDTH`,
        # or a thicker dataflow line inflates its own arrowhead right along
        # with it.
        DATAFLOW_MARKER_SIZE = 9
        # A plain relation marker's size, in its line's stroke widths.
        MARKER_SIZE = 7
        # How much bigger an arrowhead gets on a line highlighted on hover
        # (see `Stylesheet#hover_marker_css`) -- on screen, not relative to
        # the thicker line, which would double it.
        HOVER_ARROW_SCALE = 1.25

        # `drawn_edges` is the already-relation-filtered edge list (see
        # `Renderer::DrawnEdges`) -- this class has no opinion on which
        # relations are actually drawn, only how to build markers/defs for
        # whichever ones are.
        def initialize(graph, drawn_edges)
          @graph = graph
          @drawn_edges = drawn_edges
        end

        def markers_markup
          # A dataflow with no explicit `color` reuses the plain "data"
          # marker (see `Renderer::DataflowRenderer`/`marker_id`), so that
          # marker must exist even if no plain `relation "data"` edge is
          # drawn.
          markers.flat_map { |r, c| [marker_svg(r, color: c), marker_svg(r, color: c, hover: true)] }.join
        end

        # Every arrowhead marker id `markers_markup` defines, not counting
        # their `-hover` twins.
        def marker_ids = markers.map { |r, c| MarkerDefs.marker_id(r, color: c) }

        # The id of `id`'s twin for a line highlighted on hover.
        def self.hover_id(id) = "#{id}-hover"

        # A relation's marker is shared by every edge of that relation, but a
        # colored override (a dataflow's own `color`, or a plain edge's
        # `tint` resolved to a hex) needs its own marker (an arrowhead's
        # fill color is baked into its `<marker>` def) -- keyed by *both*
        # relation and color, since the same color can still need two
        # different arrow shapes (a filled "dependency" marker vs a hollow
        # "implements" one). A class method since `PathRenderer`/`Legend`
        # only need to reference a marker by id, not build the whole
        # `<defs>` block.
        def self.marker_id(relation, color: nil)
          color ? "arrow-color-#{relation}-#{color_slug(color)}" : "arrow-#{relation}"
        end

        # The CSS class `Renderer::Stylesheet` defines a `stroke:` override
        # rule under for a colored override -- same `color_slug` an
        # arrowhead marker's own id is keyed by (above), so the two never
        # drift apart for the same color value. Unlike `marker_id`, this
        # doesn't need the relation folded in too: it's always combined
        # with that edge's own `.asd-relation-<name>` class in a
        # compound selector (see `Stylesheet#line_color_css`), which
        # already disambiguates by relation. A class method for the same
        # reason `marker_id` is: `PathRenderer` only needs to reference it
        # by name, not build the whole stylesheet.
        def self.color_class(color) = "asd-dataflow-color-#{color_slug(color)}"

        def self.color_slug(color) = color.delete_prefix("#")

        private

        # `[relation, color]` per marker: one plain marker per drawn
        # relation, one per colored (relation, color) pair.
        def markers
          relations = @drawn_edges.relations
          relations += ["data"] if @graph.dataflows.any? { |df| df.color.nil? }
          relations.uniq.map { |r| [r, nil] } + colored_lines
        end

        # Every distinct (relation, color) pair actually drawn with an
        # explicit color override -- a dataflow's own `color` attr (always
        # styled as the "data" relation) or a plain edge's `tint` resolved
        # to its border color (styled as whatever relation that edge
        # actually uses). Deduped on the pair, not just the color, for the
        # same reason `marker_id` folds relation in.
        def colored_lines
          dataflow_colors = @graph.dataflows.filter_map(&:color).map { |c| ["data", c] }
          edge_colors = @drawn_edges.tinted_lines.map { |relation, tint| [relation, Tints.for(tint).border(0)] }
          (dataflow_colors + edge_colors).uniq
        end

        # `hover:` builds the marker's `-hover` twin: `HOVER_ARROW_SCALE`
        # times its on-screen size -- for a plain marker, which scales with
        # its line's stroke width, that's corrected for the highlighted
        # line's own thicker stroke.
        def marker_svg(relation, color: nil, hover: false)
          style = Relations.for(relation)
          stroke = color || style.stroke
          size = if color
                   s = hover ? DATAFLOW_MARKER_SIZE * HOVER_ARROW_SCALE : DATAFLOW_MARKER_SIZE
                   { markerUnits: "userSpaceOnUse", markerWidth: s, markerHeight: s }
                 else
                   s = hover ? MARKER_SIZE * HOVER_ARROW_SCALE * EDGE_STROKE_WIDTH / EDGE_HOVER_STROKE_WIDTH : MARKER_SIZE
                   { markerWidth: s, markerHeight: s }
                 end
          id = MarkerDefs.marker_id(relation, color: color)

          m = Markup.new
          m.element("marker", id: hover ? MarkerDefs.hover_id(id) : id, viewBox: "0 0 10 10", refX: 9, refY: 5,
                              **size, orient: "auto-start-reverse") do
            if style.arrow == :hollow
              m.element("path", d: "M 1 1 L 9 5 L 1 9", fill: "none", stroke: stroke, "stroke-width": "1.5")
            else
              m.element("path", d: "M 0 0 L 10 5 L 0 10 z", fill: stroke)
            end
          end
          m.to_s
        end
      end
    end
  end
end
