# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # Renders one already-routed dataflow as SVG markup -- routing
      # (hop-group expansion, box-nudging/stub/fork-reconciliation) lives
      # in `Archsight::Diagram::DataflowRouting`, a separate pipeline stage; this class
      # only draws.
      class DataflowRenderer
        DATAFLOW_HALO_WIDTH = 5.0

        def initialize(path_renderer:, text_renderer:, label_placer:, ids:, theme:)
          @ids = ids
          @theme = theme
          @path_renderer = path_renderer
          @text_renderer = text_renderer
          @label_placer = label_placer
        end

        # A dataflow is drawn last (after every node, edge, and implements
        # tree), so it always paints on top of the rest of the diagram, but
        # painting *after* something isn't enough to stay legible against it
        # when both use a similar thin, muted line -- especially here, where
        # a dataflow's hops often retrace an existing edge's own route
        # exactly (e.g. the physical NIC-to-LAN wiring a logical traffic path
        # rides over). A wider white halo underneath, plus a visibly thicker
        # stroke than a plain edge, makes it read as an overlay on top of the
        # diagram instead of blending into whatever's already there.
        def render(body, dataflow_waypoints)
          df = dataflow_waypoints.dataflow
          points = dataflow_waypoints.points

          # A grouped dataflow's trunk/branch pieces each carry their own
          # synthetic id ("provision_vm$branch0", see
          # `Archsight::Diagram::DataflowRouting#expanded_dataflows`) -- tagging every
          # piece with the shared *authored* id instead (an ungrouped
          # dataflow has no `origin` and passes through unchanged) is what
          # lets one legend row's hover rule (see `MarkerDefs`) reach all of
          # them at once.
          original_id = (df.origin || df).id

          body.element("g", **@ids.group_attrs(df), class: "asd-dataflow", "data-dataflow": original_id) do
            @path_renderer.draw_path_halo(body, points, curve: true, id: @ids.part(df, "halo"))
            @path_renderer.draw_relation_path(body, points, "data", color: df.color, marker_end: true, curve: true,
                                                                    css_class: "asd-dataflow-line", id: @ids.part(df, "line"))
          end

          pt = @label_placer.place_label_along(points, df.label, font_size: @theme.edge_label_font_size)
          return unless pt

          body.raw(@text_renderer.halo_text(pt[0], pt[1] - 6, df.label, font_size: @theme.edge_label_font_size,
                                                                        attrs: @ids.label_attrs(df), extra_class: "asd-dataflow-label"))
        end
      end
    end
  end
end
