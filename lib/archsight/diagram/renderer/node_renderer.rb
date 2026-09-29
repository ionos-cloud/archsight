# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # Node/container SVG markup. Delegates all shape-specific drawing to
      # `Graph::Node#representer` (see `Representers`) -- this class only
      # decides which representer/fill/stroke to use and where the label
      # sits, plus the recursive tree-walk that finds each node's box.
      class NodeRenderer
        include SvgFormat

        # `hover_sources` holds the ids of nodes with at least one drawn
        # outgoing edge: hovering one highlights those edges (see
        # `Stylesheet#edge_hover_css`), so its hover target -- a leaf's own
        # `<g>`, a container's frame -- and its label are marked for the
        # stylesheet's dim-everything-else rule.
        def initialize(boxes, text_renderer, ids:, theme:, hover_sources: Set.new)
          @boxes = boxes
          @text_renderer = text_renderer
          @ids = ids
          @hover_sources = hover_sources
          @theme = theme
        end

        # Every drawn node is wrapped in its own `<g>` (see `ElementIds`),
        # and a container's `<g>` also wraps its children's, so the document
        # tree mirrors the source's own nesting.
        def render(body, node)
          if node.anonymous?
            # A layout hint only — no box/label of its own.
            node.children.each { |c| render(body, c) }
            return
          end

          leaf_hover = HOVER_SOURCE_CLASS if node.leaf? && hover_source?(node)
          body.element("g", **@ids.group_attrs(node), class: leaf_hover) do
            if node.leaf?
              render_shape(body, node, @boxes[node.id])
            else
              render_container(body, node, @boxes[node.id])
              node.children.each { |c| render(body, c) }
            end
          end
        end

        HOVER_SOURCE_CLASS = "asd-hover-source"

        private

        def hover_source?(node) = @hover_sources.include?(node.id)

        # The class a node's hover target and label carry, if it has any
        # outgoing edge to highlight.
        def hover_class(node) = (HOVER_SOURCE_CLASS if hover_source?(node))

        def render_container(body, node, box)
          tint = Tints.for(node.effective_tint)
          level = node.tint_depth
          gradient_fill = "url(##{ContainerEffects.gradient_id(node.effective_tint, level)})"
          if node.boundary?
            rect = container_rect(box, id: @ids.part(node, "frame"), rx: 10, fill: gradient_fill, filter: "url(##{ContainerEffects.shadow_filter_id})",
                                       class: ["asd-container-boundary", tint.border_class(level), "asd-stroke-application", hover_class(node)])
            body.raw(@text_renderer.wrap_link(rect, node.link))
            body.raw(@text_renderer.halo_text(box.left + @theme.title_inset_x, box.top + @theme.boundary_title_baseline, node.label,
                                              font_size: @theme.boundary_title_font_size, weight: "bold",
                                              anchor: "start", link: node.link, attrs: @ids.label_attrs(node), extra_class: hover_class(node)))
          else
            rect = container_rect(box, id: @ids.part(node, "frame"), rx: 8, fill: gradient_fill,
                                       class: ["asd-container", tint.border_class(level), hover_class(node)])
            body.raw(@text_renderer.wrap_link(rect, node.link))
            body.raw(@text_renderer.halo_text(box.left + @theme.title_inset_x, box.top + @theme.group_title_baseline, node.label,
                                              font_size: @theme.group_title_font_size, weight: "bold",
                                              anchor: "start", link: node.link, attrs: @ids.label_attrs(node), extra_class: hover_class(node)))
          end
        end

        def container_rect(box, id:, **style)
          m = Markup.new
          m.element("rect", id: id, x: fmt(box.left), y: fmt(box.top), width: fmt(box.width), height: fmt(box.height), **style)
          m.to_s
        end

        # Every shape's own figure geometry/label position/label size comes
        # from its representer (`figure_geometry`/`label_x`/`label_y`/
        # `label_font_size` -- identity/the theme's node font size for every shape but `actor`,
        # whose figure and label occupy their own separate bands); this
        # method only picks fill/stroke (from the node's own tint, with
        # `application?` keeping its own thicker stroke width) and wires the
        # two together.
        def render_shape(body, node, box)
          representer = node.representer
          tint = Tints.for(node.effective_tint)
          level = node.tint_depth
          style = { fill_class: tint.fill_class(level), stroke_class: tint.border_class(level),
                    width_class: node.application? ? "asd-stroke-application" : "asd-stroke-thin" }

          cx, cy, w, h = representer.figure_geometry(box, @theme)
          body.raw(@text_renderer.wrap_link(representer.markup(cx, cy, w, h, id: @ids.id(node), **style), node.link))
          body.raw(@text_renderer.label_text(representer.label_x(box), representer.label_y(box, @theme), node.label,
                                             font_size: representer.label_font_size(@theme), link: node.link,
                                             attrs: @ids.label_attrs(node), extra_class: hover_class(node)))
        end
      end
    end
  end
end
