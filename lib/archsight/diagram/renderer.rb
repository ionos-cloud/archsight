# frozen_string_literal: true

require_relative "routing/edge_router"
require_relative "routing/edge_routing"
require_relative "routing/dataflow_routing"
require_relative "layout"
require_relative "graph"
require_relative "style/representers"
require_relative "style/relations"
require_relative "style/tints"
require_relative "renderer/svg_format"
require_relative "renderer/markup"
require_relative "renderer/element_ids"
require_relative "renderer/id_namespace"
require_relative "renderer/path_geometry"
require_relative "renderer/text_renderer"
require_relative "renderer/drawn_edges"
require_relative "renderer/marker_defs"
require_relative "renderer/container_effects"
require_relative "renderer/path_renderer"
require_relative "renderer/label_placer"
require_relative "renderer/node_renderer"
require_relative "renderer/implements_tree_renderer"
require_relative "renderer/edge_renderer"
require_relative "renderer/dataflow_renderer"
require_relative "renderer/stylesheet"
require_relative "renderer/legend_renderer"

module Archsight
  module Diagram
    # Renders a Graph plus its computed Layout into an SVG document string.
    class Renderer
      include SvgFormat

      # A dataflow's line is visibly thicker than a plain edge's (see
      # `DataflowRenderer#render`), and its legend sample/hover-highlighted
      # width scale off this same value (see `MarkerDefs`/`Legend::Row`).
      DATAFLOW_STROKE_WIDTH = 2.0

      # A plain edge's line (`.asd-stroke-thin`), and how thick it gets
      # while highlighted on hover (see `Stylesheet#edge_hover_css`).
      EDGE_STROKE_WIDTH = 1.5
      EDGE_HOVER_STROKE_WIDTH = 3.0

      # The canvas is sized from the boxes (`Layout`'s own margin), but a
      # routed line can run further out than that -- a bridge looping
      # around the whole diagram on an outer lane (see
      # `EdgeRouter::BridgePath::BRIDGE_LANES`). The canvas grows to take in
      # every routed point plus this much, for the line's own stroke and
      # arrowhead, so nothing is clipped at the canvas edge.
      EDGE_CANVAS_OVERHANG = 4.0

      def self.render(graph, layout, relation_filter: Relations::DEFAULT_FILTER, style: nil, id_prefix: nil)
        new(graph, layout, relation_filter: relation_filter, style: style, id_prefix: id_prefix).render
      end

      def initialize(graph, layout, relation_filter: Relations::DEFAULT_FILTER, style: nil, id_prefix: nil)
        @id_prefix = id_prefix
        @graph = graph
        @layout = layout
        @boxes = layout.boxes
        theme = layout.theme
        @relation_filter = relation_filter
        @style = style
        @text_renderer = TextRenderer.new
        @ids = ElementIds.new(@graph)
        drawn_edges_view = DrawnEdges.new(drawn_edges)
        @marker_defs = MarkerDefs.new(@graph, drawn_edges_view)
        @container_effects = ContainerEffects.new(@graph)
        @stylesheet = Stylesheet.new(@graph, drawn_edges_view, ids: @ids, tree_ids: tree_ids, marker_ids: @marker_defs.marker_ids,
                                                               theme: theme)
        @path_renderer = PathRenderer.new
        nodes = @graph.nodes_by_id.values
        # The legend's frame is as solid as a node box, as far as a label is
        # concerned.
        legend_boxes = @layout.legend ? @boxes.slice(@layout.legend.frame.id) : {}
        @label_placer = LabelPlacer.new(@boxes.slice(*nodes.select(&:leaf?).map(&:id)).merge(legend_boxes),
                                        containers: @boxes.slice(*nodes.reject { |n| n.leaf? || n.anonymous? }.map(&:id)))
        @node_renderer = NodeRenderer.new(@boxes, @text_renderer, ids: @ids, theme: theme,
                                                                  hover_sources: drawn_edges.to_set { |e| e.from.id })
        @implements_tree_renderer = ImplementsTreeRenderer.new(@boxes, path_renderer: @path_renderer, text_renderer: @text_renderer,
                                                                       ids: @ids, theme: theme)
        # Both routing stages avoid the same boxes, so they share one map
        # (and, with the native kernels, one packed box table).
        obstacle_map = ObstacleMap.new(@boxes, ignoring: nodes.select { |n| n.anonymous? && !n.leaf? }.map(&:id))
        @edge_routing = EdgeRouting.new(@graph, @boxes, obstacle_map: obstacle_map)
        @edge_renderer = EdgeRenderer.new(path_renderer: @path_renderer, text_renderer: @text_renderer, label_placer: @label_placer,
                                          ids: @ids, theme: theme)
        @dataflow_routing = DataflowRouting.new(@graph, @boxes, obstacle_map: obstacle_map)
        @dataflow_renderer = DataflowRenderer.new(path_renderer: @path_renderer, text_renderer: @text_renderer, label_placer: @label_placer,
                                                  ids: @ids, theme: theme)
        @legend_renderer = LegendRenderer.new(text_renderer: @text_renderer)
      end

      def render
        body = Markup.new
        @graph.roots.each { |node| @node_renderer.render(body, node) }

        # Tree lines are fixed by the boxes alone, so plain edges can route
        # around them like any other line.
        trees = implements_tree_groups.map { |target, edges| [target, edges, @implements_tree_renderer.segments(edges, target)] }
        tree_paths = trees.flat_map { |*, tree| tree.paths }

        edge_paths = @edge_routing.compute_paths(individually_routed_edges)
        @edge_routing.refine_line_overlap!(edge_paths, fixed_paths: tree_paths)
        @edge_routing.separate_bridge_lanes!(edge_paths, fixed_paths: tree_paths)
        @edge_routing.assign_ports!(edge_paths)
        dataflow_routes = @dataflow_routing.compute_routes(edge_paths.map(&:points))

        # Every line is known before any label is placed, so each label can
        # keep clear of lines drawn after it too (see `LabelPlacer`).
        @label_placer.register_paths(edge_paths.map(&:points) + tree_paths + dataflow_routes.map(&:points))

        edge_paths.each { |ep| @edge_renderer.render(body, ep.edge, ep.points) }
        trees.each { |target, edges, tree| @implements_tree_renderer.render(body, edges, target, tree: tree) }
        dataflow_routes.each { |dp| @dataflow_renderer.render(body, dp) }

        left, top, right, bottom = canvas_extent(edge_paths.map(&:points) + dataflow_routes.map(&:points))
        width = right - left
        # The legend is part of the layout (see `Layout#place_legend`), so
        # the canvas extent already takes it in.
        legend_svg = @layout.legend ? @legend_renderer.render(@layout.legend, @boxes) : ""
        total_height = bottom - top

        # All text is collected into `@text_renderer` by `halo_text` instead
        # of being interleaved into `body`/`legend_svg`, and emitted here as
        # the last thing in the document -- SVG has no z-index, paint
        # order is document order, so this guarantees every label paints
        # on top of every shape/edge/legend background, never the reverse.
        text_layer = @text_renderer.texts.join

        svg = Markup.new
        svg.element("svg", xmlns: "http://www.w3.org/2000/svg",
                           viewBox: "#{origin(left)} #{origin(top)} #{fmt(width)} #{fmt(total_height)}",
                           width: fmt(width), height: fmt(total_height), "font-family": "Helvetica, Arial, sans-serif") do
          svg.element("defs") do
            svg.raw(@marker_defs.markers_markup)
            svg.raw(@container_effects.defs_markup)
          end
          svg.raw(@stylesheet.style_block) if embed_style?
          svg.raw(@stylesheet.interaction_style_block)
          svg.element("rect", id: "asd-canvas-bg", x: origin(left), y: origin(top), width: fmt(width), height: fmt(total_height),
                              class: "asd-canvas-bg")
          svg.raw(body.to_s)
          svg.raw(legend_svg)
          svg.raw(text_layer)
        end

        markup = svg.to_s
        markup = IdNamespace.apply(markup, @id_prefix) if @id_prefix
        %(<?xml version="1.0" encoding="UTF-8"?>\n#{stylesheet_pi}) + markup
      end

      private

      # `[left, top, right, bottom]` of the canvas: the layout's own
      # `[0, 0, width, height]`, grown to take in every routed point (see
      # `EDGE_CANVAS_OVERHANG`) and the legend (with the canvas margin
      # around it -- `Layout.attach_legend` can put one left of or above
      # boxes that were never normalized onto the canvas). `left`/`top` go
      # negative for a line looping out past the top/left edge -- the
      # `viewBox` origin moves with them rather than every coordinate being
      # shifted.
      def canvas_extent(paths)
        extents = paths.flatten(1).map { |x, y| [x, y, EDGE_CANVAS_OVERHANG] }
        if @layout.legend
          frame = @boxes[@layout.legend.frame.id]
          margin = @layout.theme.canvas_margin
          extents << [frame.left, frame.top, margin] << [frame.right, frame.bottom, margin]
        end
        return [0.0, 0.0, @layout.width, @layout.height] if extents.empty?

        [[0.0, extents.map { |x, _, pad| x - pad }.min].min, [0.0, extents.map { |_, y, pad| y - pad }.min].min,
         [@layout.width, extents.map { |x, _, pad| x + pad }.max].max, [@layout.height, extents.map { |_, y, pad| y + pad }.max].max]
      end

      # A canvas origin coordinate: a bare `0` for the usual unshifted
      # canvas, else formatted.
      def origin(value) = value.zero? ? 0 : fmt(value)

      # `@style` controls `@stylesheet.style_block` -- the swappable
      # *presentation* rules only (see `Stylesheet`'s own docs; its
      # `interaction_style_block`, the hover/`:has()` rules the diagram's
      # own legend-hover highlight depends on, is always embedded regardless,
      # a few lines below this). Unset (the default) embeds `style_block`;
      # `"none"` omits it entirely -- every element still
      # carries its `class="..."` attributes, just with no presentation
      # rules anywhere in the document, for a caller supplying its own CSS
      # externally (e.g. one shared stylesheet already loaded by a page
      # embedding several of these diagrams, instead of every one repeating
      # an identical embedded copy); anything else is treated as a URL and
      # linked instead via an `<?xml-stylesheet?>` processing instruction
      # (the standard way a *standalone* SVG file references an external
      # stylesheet -- unlike a `<link>`, which only does anything once the
      # SVG is inlined into an HTML document) rather than embedded.
      def embed_style?
        @style.nil?
      end

      def external_style_url
        @style unless @style.nil? || @style == "none"
      end

      def stylesheet_pi
        return "" unless external_style_url

        %(<?xml-stylesheet type="text/css" href="#{escape(external_style_url)}"?>\n)
      end

      def drawn_edges
        @drawn_edges ||= @graph.edges.select { |e| @relation_filter.include?(e.relation) }
      end

      # `implements` is conventionally drawn as a tree when several things
      # implement the same target: each implementer gets a short branch to
      # a shared spine, and one trunk with a single arrowhead carries the
      # relationship the rest of the way in, instead of every implementer
      # drawing its own full, independently-routed line. Only kicks in for
      # groups of two or more -- a target with a single implementer has no
      # sibling to share a spine with, so it just reads as an ordinary
      # individual edge -- and only for edges a user hasn't customized (an
      # explicit `style` or `tint`) or given an unusual direction, so an
      # edge someone deliberately shaped/colored by hand is never silently
      # folded into the tree.
      def implements_tree_groups
        # Grouped by `to.id` (a plain string), not `to` itself: `Node` and
        # `Edge` are Structs with circular `parent` <-> `children`
        # references, so anything that hashes them (`group_by(&:to)`,
        # `Array#-`, Hash-keying) would recurse forever computing their
        # default `hash`/`==`.
        @implements_tree_groups ||=
          drawn_edges
          .select { |e| e.relation_type.tree_grouped? && e.direction == :directed && !e.attrs.key?("style") && e.tint.nil? }
          .group_by { |e| e.to.id }
          .filter_map { |_id, edges| [edges.first.to, edges] if edges.length > 1 }
      end

      # Every implements-tree-grouped edge (by identity) to its tree's id.
      def tree_ids
        implements_tree_groups.each_with_object({}.compare_by_identity) do |(target, edges), ids|
          edges.each { |e| ids[e] = @ids.tree(target) }
        end
      end

      def tree_grouped_edges
        @tree_grouped_edges ||= implements_tree_groups.flat_map { |_target, edges| edges }
      end

      # --- edges -------------------------------------------------------------

      def individually_routed_edges
        excluded = tree_grouped_edges.to_set.compare_by_identity
        drawn_edges.reject { |e| excluded.include?(e) }
      end
    end
  end
end
