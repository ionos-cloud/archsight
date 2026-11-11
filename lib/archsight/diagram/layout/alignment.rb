# frozen_string_literal: true

module Archsight
  module Diagram
    class Layout
      # `align "top other"` (or `left`, `center`, `right`, `middle`, `bottom`; a bare id is `center`): once
      # everything is placed, a node moves until that edge of it lines up with the same edge of the other node,
      # which may sit in another container -- like the align buttons of a drawing editor. It only uses the
      # free room its container already has, never growing one: where its container packs along that axis (a
      # `layer` for left/right, a `stack` for up/down) it pushes its siblings along, keeping their order and
      # gaps; elsewhere it moves within the container's inner box. It stops as close as it gets.
      class Alignment
        # Shifts below this are left alone (no visible change, no churn).
        EPSILON = 0.5

        AXES = { x: Axis::WIDTH, y: Axis::HEIGHT }.freeze

        def initialize(graph, boxes, theme:)
          @graph = graph
          @boxes = boxes
          @theme = theme
        end

        def apply
          aligned = @graph.nodes_by_id.values.select(&:align)
          return if aligned.empty?

          # A second round settles a node aligned to a node that is aligned itself.
          2.times do
            aligned.each { |node| node.alignments.each { |axis, edge, id| align(node, AXES.fetch(axis), edge, id) } }
          end
        end

        private

        def align(node, axis, edge, target_id)
          delta = wanted(axis, edge, @boxes[target_id]) - wanted(axis, edge, @boxes[node.id])
          return if delta.abs < EPSILON

          lo, hi = room(node, axis)
          parent = node.parent
          if parent && parent.main_axis == axis
            sweep(parent.children.sort_by { |c| axis.position(@boxes[c.id]) }, node, axis, delta, lo, hi)
          else
            box = @boxes[node.id]
            shift(node, axis, delta.clamp([lo - axis.leading_edge(box), 0.0].min, [hi - axis.trailing_edge(box), 0.0].max))
          end
          refit(parent, axis)
        end

        # The coordinate of `box` that `edge` lines up.
        def wanted(axis, edge, box)
          case edge
          when "left", "top" then axis.leading_edge(box)
          when "right", "bottom" then axis.trailing_edge(box)
          else axis.position(box)
          end
        end

        # The children of a container packed along `axis`, in order, with `node` wanting to move by `delta`: the
        # others stay where they are unless they come closer to a neighbour than `min_gap`, then they are pushed
        # along; everything stays inside `lo..hi`.
        def sweep(children, node, axis, delta, lo, hi)
          boxes = children.map { |c| @boxes[c.id] }
          sizes = boxes.map { |b| axis.size(b) }
          gaps = children.each_cons(2).map { |a, b| min_gap(a, b, axis) }
          leads = boxes.each_with_index.map { |b, i| axis.leading_edge(b) + (children[i].equal?(node) ? delta : 0.0) }

          push_on(leads, sizes, gaps)
          leads[-1] = [leads[-1], hi - sizes[-1]].min
          (leads.length - 2).downto(0) { |i| leads[i] = [leads[i], leads[i + 1] - gaps[i] - sizes[i]].min }
          leads[0] = [leads[0], lo].max
          push_on(leads, sizes, gaps)

          children.each_with_index { |c, i| shift(c, axis, leads[i] - axis.leading_edge(boxes[i])) }
        end

        # How close two neighbours may come: the sibling gap plus half a port tab on each side that faces the
        # other (see `RankArranger#port_overhangs`), never more than they are apart now.
        def min_gap(a, b, axis)
          current = [axis.leading_edge(@boxes[b.id]) - axis.trailing_edge(@boxes[a.id]), 0.0].max
          trailing, leading = axis == Axis::HEIGHT ? %w[bottom top] : %w[right left]
          [current, @theme.sibling_gap + tab_overhang(a, trailing) + tab_overhang(b, leading)].min
        end

        def tab_overhang(node, side)
          return 0.0 unless node.leaf? && node.ports.any? { |p| p.side.nil? || p.side == side }

          PortMetrics.new(@theme).height / 2.0
        end

        # Each leading edge at least its gap past the box before it.
        def push_on(leads, sizes, gaps)
          (1...leads.length).each { |i| leads[i] = [leads[i], leads[i - 1] + sizes[i - 1] + gaps[i - 1]].max }
        end

        # The room (lo, hi) a node may move in along `axis`: its container's inner box. An anonymous container
        # packing along that axis is only as long as its children, so its room is that of its own container
        # (one packing across it is as long as the line it sits in). Top-level nodes may use the whole drawing.
        def room(node, axis)
          container = node.parent
          container = container.parent while container&.anonymous? && container.main_axis == axis
          unless container
            all = @graph.roots.map { |r| @boxes[r.id] }
            return [all.map { |b| axis.leading_edge(b) }.min, all.map { |b| axis.trailing_edge(b) }.max]
          end

          box = @boxes[container.id]
          padding = container.layout_padding(@theme)
          title = axis == Axis::HEIGHT ? container.layout_title_height(@theme) : 0.0
          [axis.leading_edge(box) + padding + title, axis.trailing_edge(box) - padding]
        end

        def shift(node, axis, delta)
          return if delta.abs < EPSILON

          box = @boxes[node.id]
          axis.set_position(box, axis.position(box) + delta)
          node.children.each { |c| shift(c, axis, delta) }
        end

        # An anonymous layer/stack's box follows its children (it draws nothing, but routing and the
        # alignment of its own parent read it).
        def refit(container, axis)
          while container&.anonymous?
            boxes = container.children.map { |c| @boxes[c.id] }
            box = @boxes[container.id]
            lead = boxes.map { |b| axis.leading_edge(b) }.min
            trail = boxes.map { |b| axis.trailing_edge(b) }.max
            axis.set_position(box, (lead + trail) / 2.0)
            axis.set_size(box, trail - lead)
            container = container.parent
          end
        end
      end
    end
  end
end
