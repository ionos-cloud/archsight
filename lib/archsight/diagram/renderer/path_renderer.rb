# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # Turns a point list into styled `<path>` markup -- shared by plain
      # edges, dataflows, and the implements-tree, which all need the same
      # relation-styled line/halo drawing.
      class PathRenderer
        # The bit that's just "draw a path styled for this relation" --
        # shared by a plain edge and the implements-tree's spine/branch
        # segments, which need the same dash/stroke styling but never carry
        # their own arrowhead (only the tree's single trunk segment does).
        # `color:` is a dataflow's own optional override (an arbitrary,
        # unbounded user string, unlike everything else here -- see
        # `Renderer::Stylesheet`/`MarkerDefs.color_class` for how that still
        # becomes a CSS class instead of an inline `stroke=`); `css_class:`
        # replaces the default `asd-stroke-thin` width when the caller
        # needs its own (only a dataflow's thicker, hover-animated line does).
        def draw_relation_path(body, points, relation, marker_end: false, marker_start: false, color: nil, curve: false,
                               css_class: nil, id: nil)
          path_d = PathGeometry.path_d_string(points, curve: curve)
          marker_id = "url(##{MarkerDefs.marker_id(relation, color: color)})"

          body.element("path", id: id, d: path_d,
                               class: ["asd-line", "asd-relation-#{relation}", css_class || "asd-stroke-thin",
                                       (MarkerDefs.color_class(color) if color)],
                               "marker-end": (marker_id if marker_end),
                               "marker-start": (marker_id if marker_start))
        end

        # An invisible, much wider copy of an edge's line, drawn on top of
        # it purely to catch the pointer -- a 1.5px line is too thin to
        # hover reliably (see `Stylesheet#edge_hover_css`).
        def draw_hit_path(body, points, curve: false, id: nil)
          body.element("path", id: id, d: PathGeometry.path_d_string(points, curve: curve), class: "asd-hit")
        end

        # A plain white, wider, undashed underlay for a dataflow's own path
        # -- drawn first so the colored line on top of it stays legible even
        # crossing a dark box outline or another edge's line, the same idea
        # as `TextRenderer#halo_text`'s stroke-behind-fill halo, just for
        # lines instead of glyphs.
        def draw_path_halo(body, points, curve: false, id: nil)
          path_d = PathGeometry.path_d_string(points, curve: curve)
          body.element("path", id: id, d: path_d, class: "asd-dataflow-halo")
        end
      end
    end
  end
end
