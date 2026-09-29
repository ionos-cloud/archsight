# frozen_string_literal: true

require_relative "path_metrics"

module Archsight
  module Diagram
    module EdgeRouter
      # The direct-line candidate family: a straight line between two boxes'
      # anchor points, or (when the boxes happen to share a flush edge) a
      # straight orthogonal line through the smaller box's own center.
      module StraightPath
        module_function

        def straight_path(a, b, from_shape: "rectangle", to_shape: "rectangle")
          unless Representers.for(from_shape).elliptical? || Representers.for(to_shape).elliptical?
            shared = shared_edge_path(a, b)
            return shared if shared
          end

          [anchor_point(a, b.x, b.y, shape: from_shape), anchor_point(b, a.x, a.y, shape: to_shape)]
        end

        # When two boxes share a flush left/right or top/bottom line (e.g. a
        # wide box directly above a narrower one that's flush with one of its
        # sides), the generic center-to-center ray in `anchor_point` exits
        # through the *wrong* side of the wider box, drawing a visibly
        # diagonal line despite the boxes lining up. In that case, route a
        # straight orthogonal line instead, through the *smaller* box's
        # center on the shared axis — its center is guaranteed to fall within
        # the larger box's span on that axis, since the smaller box is flush
        # against one of the larger box's edges.
        def shared_edge_path(a, b)
          vertical = !a.overlaps_y?(b) && (PathMetrics.close?(a.left, b.left) || PathMetrics.close?(a.right, b.right))
          horizontal = !a.overlaps_x?(b) && (PathMetrics.close?(a.top, b.top) || PathMetrics.close?(a.bottom, b.bottom))

          return vertical_shared_edge_path(a, b) if vertical && !horizontal
          return horizontal_shared_edge_path(a, b) if horizontal && !vertical

          nil
        end

        # Always returns `a`'s point first, `b`'s second -- regardless of
        # which is physically above/below or left/right -- so the edge's
        # actual direction (and its arrowhead) is preserved. `a`/`b` here
        # are already known to sit side by side vertically (no x overlap,
        # flush top or bottom), so whichever is geometrically on top always
        # exits through its own *bottom* and the other through its *top*.
        def vertical_shared_edge_path(a, b)
          smaller = a.width <= b.width ? a : b
          a_above_b = a.y <= b.y
          [[smaller.x, a_above_b ? a.bottom : a.top], [smaller.x, a_above_b ? b.top : b.bottom]]
        end

        # The transpose of `vertical_shared_edge_path`.
        def horizontal_shared_edge_path(a, b)
          smaller = a.height <= b.height ? a : b
          a_left_of_b = a.x <= b.x
          [[a_left_of_b ? a.right : a.left, smaller.y], [a_left_of_b ? b.left : b.right, smaller.y]]
        end

        # Finds where a line from box's center toward (tx, ty) crosses the
        # box's boundary — rectangular by default, or the ellipse inscribed in
        # the box when `shape` renders as an ellipse -- then lets that shape's
        # own representer nudge the result back onto its real outline if it
        # landed somewhere the outline doesn't actually cover (see
        # `Representers::Base#correct_anchor_point`; a no-op for every shape
        # but `file`, whose folded corner cuts a triangle out of the box).
        def anchor_point(box, tx, ty, shape: "rectangle")
          dx = tx - box.x
          dy = ty - box.y
          return [box.x, box.y] if dx.zero? && dy.zero?

          half_w = box.width / 2.0
          half_h = box.height / 2.0

          representer = Representers.for(shape)
          scale = if representer.elliptical?
                    1.0 / Math.sqrt(((dx / half_w)**2) + ((dy / half_h)**2))
                  else
                    scale_x = dx.zero? ? Float::INFINITY : (half_w / dx.abs)
                    scale_y = dy.zero? ? Float::INFINITY : (half_h / dy.abs)
                    [scale_x, scale_y].min
                  end

          point = [box.x + (dx * scale), box.y + (dy * scale)]
          representer.correct_anchor_point(box, dx, dy, point)
        end
      end
    end
  end
end
