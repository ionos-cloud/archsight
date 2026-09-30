# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # Renders one already-routed plain edge as SVG markup -- routing
      # (obstacle computation, line-overlap refinement, port-splitting)
      # lives in `Archsight::Diagram::EdgeRouting`, a separate pipeline stage; this
      # class only draws.
      class EdgeRenderer
        def initialize(path_renderer:, text_renderer:, label_placer:, ids:, theme:)
          @ids = ids
          @theme = theme
          @path_renderer = path_renderer
          @text_renderer = text_renderer
          @label_placer = label_placer
        end

        def render(body, edge, points)
          # Resolved to a hex here (not passed as a raw tint name) so it
          # flows through the exact same `color:` override pathway a
          # dataflow's own `color` attr already uses -- one line/arrowhead
          # recoloring mechanism, not two. Level 0 always: an edge doesn't
          # nest, so there's no darkening depth to pick.
          color = edge.tint && Tints.for(edge.tint).border(0)

          curve = edge.relation_type.curved?
          body.element("g", **@ids.group_attrs(edge), class: "asd-edge") do
            @path_renderer.draw_relation_path(body, points, edge.relation,
                                              marker_end: edge.direction != :undirected,
                                              marker_start: edge.direction == :bidirectional,
                                              curve: curve, color: color, id: @ids.part(edge, "line"))
            @path_renderer.draw_hit_path(body, points, curve: curve, id: @ids.part(edge, "hit"))
          end

          pt = @label_placer.place_label_along(points, edge.label, font_size: @theme.edge_label_font_size)
          return unless pt

          body.raw(@text_renderer.halo_text(pt[0], pt[1] - 6, edge.label, font_size: @theme.edge_label_font_size,
                                                                          attrs: @ids.label_attrs(edge), extra_class: "asd-edge-label"))
        end
      end
    end
  end
end
