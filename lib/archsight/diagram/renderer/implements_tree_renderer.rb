# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # Draws one `implements` group as a tree instead of `edges.length`
      # independent lines: each source gets a short branch straight to a
      # shared spine, and a single trunk (with the one arrowhead) carries
      # the relationship the rest of the way into the target. Orientation
      # follows whichever axis separates the sources from the target more,
      # on average -- vertical when they're predominantly above/below it,
      # horizontal when predominantly left/right. Deliberately does not run
      # obstacle-avoidance, line-overlap refinement, or port-splitting for
      # this geometry (unlike individually-routed edges) -- a first, simple
      # pass, not a full port of that machinery.
      class ImplementsTreeRenderer
        # How much of the gap between the implementers' near edge and the
        # target's near edge a tree's branches occupy, vs. its trunk -- a
        # tree conventionally merges close to the implementors (short
        # branches) with one longer trunk carrying the rest of the way to
        # the target, not a plain 50/50 split down the middle.
        TREE_BRANCH_FRACTION = 0.3

        # The spine/trunk belong to no single edge, so they dim as one while
        # anything is hovered (see `Stylesheet#edge_hover_css`) -- marked on
        # the paths themselves, since dimming the tree's own `<g>` would dim
        # every stub `<g>` inside it too, beyond any rule's reach to undo.
        TREE_LINE_CLASSES = %w[asd-stroke-thin asd-tree-line].freeze

        def initialize(boxes, path_renderer:, text_renderer:, ids:, theme:)
          @boxes = boxes
          @ids = ids
          @theme = theme
          @path_renderer = path_renderer
          @text_renderer = text_renderer
        end

        # One tree's geometry: the shared spine, one stub per implementing
        # edge (in `edges` order), and the trunk into the target.
        Segments = Struct.new(:spine, :stubs, :trunk, keyword_init: true) do
          def paths = [spine, *stubs, trunk]
        end

        # `tree` is `segments(edges, target)`, when the caller already has it.
        def render(body, edges, target, tree: segments(edges, target))
          # The tree as a whole has no source object of its own -- it's
          # named after its target (see `ElementIds#tree`) -- but each stub
          # still sits in its own edge's `<g>`, same as an individually
          # routed edge.
          @tree_id = @ids.tree(target)
          body.element("g", id: @tree_id, "data-asd-kind": "implements-tree", "data-asd-src": target.id) do
            @path_renderer.draw_relation_path(body, tree.spine, "implements", css_class: TREE_LINE_CLASSES, id: "#{@tree_id}__spine")
            edges.zip(tree.stubs) { |edge, stub| render_stub(body, edge, stub) }
            @path_renderer.draw_relation_path(body, tree.trunk, "implements", marker_end: true, css_class: TREE_LINE_CLASSES,
                                                                              id: "#{@tree_id}__trunk")
          end
        end

        # Where a tree's lines go, without drawing them -- `Renderer` also
        # hands these to `LabelPlacer` up front, so every other label can
        # steer clear of them (see `LabelPlacer#register_paths`).
        def segments(edges, target)
          target_box = @boxes[target.id]
          sources = edges.map { |e| @boxes[e.from.id] }

          avg_dx = (sources.sum(&:x) / sources.length.to_f) - target_box.x
          avg_dy = (sources.sum(&:y) / sources.length.to_f) - target_box.y

          if avg_dy.abs >= avg_dx.abs
            vertical_segments(sources, target_box, below: avg_dy.positive?)
          else
            horizontal_segments(sources, target_box, right: avg_dx.positive?)
          end
        end

        private

        def vertical_segments(sources, target_box, below:)
          spine_y = below ? spine_coord(target_box.bottom, sources.map(&:top).min) : spine_coord(target_box.top, sources.map(&:bottom).max)
          xs = sources.map(&:x) + [target_box.x]
          stubs = sources.map { |source| [[source.x, below ? source.top : source.bottom], [source.x, spine_y]] }
          entry_y = below ? target_box.bottom : target_box.top

          Segments.new(spine: [[xs.min, spine_y], [xs.max, spine_y]], stubs: stubs,
                       trunk: [[target_box.x, spine_y], [target_box.x, entry_y]])
        end

        def horizontal_segments(sources, target_box, right:)
          spine_x = right ? spine_coord(target_box.right, sources.map(&:left).min) : spine_coord(target_box.left, sources.map(&:right).max)
          ys = sources.map(&:y) + [target_box.y]
          stubs = sources.map { |source| [[right ? source.right : source.left, source.y], [spine_x, source.y]] }
          entry_x = right ? target_box.right : target_box.left

          Segments.new(spine: [[spine_x, ys.min], [spine_x, ys.max]], stubs: stubs,
                       trunk: [[spine_x, target_box.y], [entry_x, target_box.y]])
        end

        def render_stub(body, edge, stub)
          body.element("g", **@ids.group_attrs(edge), class: "asd-edge") do
            @path_renderer.draw_relation_path(body, stub, "implements", id: @ids.part(edge, "line"))
            @path_renderer.draw_hit_path(body, stub, id: @ids.part(edge, "hit"))
          end
          return unless edge.label

          mid = Geometry.path_midpoint(stub)
          body.raw(@text_renderer.halo_text(mid[0], mid[1] - 6, edge.label, font_size: @theme.edge_label_font_size,
                                                                            attrs: @ids.label_attrs(edge), extra_class: "asd-edge-label"))
        end

        # `target_edge` and `source_edge` are the two boxes' near edges
        # facing each other; returns the spine coordinate `TREE_BRANCH_FRACTION`
        # of the way back from `source_edge` towards `target_edge` (so the
        # branch -- source to spine -- is the short leg, and the trunk --
        # spine to target -- is the long one).
        def spine_coord(target_edge, source_edge)
          target_edge + ((source_edge - target_edge) * (1 - TREE_BRANCH_FRACTION))
        end
      end
    end
  end
end
