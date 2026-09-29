# frozen_string_literal: true

module Archsight
  module Diagram
    # Pure point-list math with no SVG/rendering concern -- polyline
    # length, "point at fraction X along this polyline", perpendicular
    # distance, Ramer-Douglas-Peucker simplification, and turn-angle
    # limiting/measurement. Used by both routing stages (`EdgeRouting`/
    # `DataflowRouting`, which must never depend on `Renderer`) and by
    # `Renderer`'s own path-drawing/label-placement code (see
    # `Renderer::PathGeometry`, which keeps the SVG `d`-string builders and
    # delegates its pure-math methods here). Stateless, like `EdgeRouter`.
    module Geometry
      module_function

      def point_distance(a, b)
        Math.hypot(b[0] - a[0], b[1] - a[1])
      end

      def path_length(points)
        points.each_cons(2).sum { |a, b| point_distance(a, b) }
      end

      # The point at `fraction` of the way along the path's total length --
      # `path_midpoint` is just `point_along(points, 0.5)`.
      def point_along(points, fraction)
        return points.first if points.length == 1

        segments = points.each_cons(2).map { |a, b| point_distance(a, b) }
        remaining = segments.sum * fraction

        points.each_cons(2).with_index do |((x1, y1), (x2, y2)), i|
          seg_len = segments[i]
          if remaining <= seg_len
            t = seg_len.zero? ? 0.0 : remaining / seg_len
            return [x1 + ((x2 - x1) * t), y1 + ((y2 - y1) * t)]
          end
          remaining -= seg_len
        end

        points.last
      end

      # The point exactly halfway along the path's total length -- not
      # `points[points.length / 2]`, which for a straight (2-point) edge is
      # just index 1, i.e. the "to" endpoint itself, not its center.
      def path_midpoint(points)
        point_along(points, 0.5)
      end

      # Perpendicular distance from `point` to the line through `a`/`b`
      # (falling back to plain point-to-point distance when `a` and `b`
      # coincide, so a zero-length chord never divides by zero).
      def point_to_segment_distance(point, a, b)
        length = point_distance(a, b)
        return point_distance(point, a) if length.zero?

        (((b[0] - a[0]) * (a[1] - point[1])) - ((a[0] - point[0]) * (b[1] - a[1]))).abs / length
      end

      # Ramer-Douglas-Peucker: reduces `points` to the fewest points that
      # still keep the polyline within `tolerance` of its original shape.
      # `EdgeRouter.route` includes every corner needed to route a *plain*
      # edge cleanly around obstacles, but a dataflow's stylized overlay
      # doesn't need to visually conform to each one -- fitting the
      # smoothing spline through fewer, more meaningful points yields a
      # more direct curve. Always keeps the first and last point, so it
      # composes safely with the nudge/stub logic that runs on exactly
      # those afterward.
      def simplify_points(points, tolerance)
        return points if points.length < 3

        first = points.first
        last = points.last
        max_dist = 0.0
        max_index = 0

        points[1..-2].each_with_index do |point, i|
          dist = point_to_segment_distance(point, first, last)
          if dist > max_dist
            max_dist = dist
            max_index = i + 1
          end
        end

        if max_dist > tolerance
          left = simplify_points(points[0..max_index], tolerance)
          right = simplify_points(points[max_index..], tolerance)
          left[0..-2] + right
        else
          [first, last]
        end
      end

      # How many full sweeps `limit_turn_angles` makes over every interior
      # point -- relaxing one point changes the turn angle its immediate
      # neighbors see too, so a single pass doesn't fully settle a chain of
      # several sharp corners.
      ANGLE_RELAXATION_PASSES = 40

      # Caps the turn angle at every interior point of `points` (the true
      # first/last points are never touched, preserving the endpoint
      # stub's exit direction) by pulling any offending point toward the
      # midpoint of its two neighbors -- moving a point toward that
      # midpoint monotonically straightens the bend there, so a small
      # binary search lands the turn angle exactly at the cap instead of
      # overshooting into some other, still-arbitrary shape.
      def limit_turn_angles(points, max_turn_degrees)
        return points if points.length < 3

        relaxed = points.map(&:dup)
        indices = (1...(relaxed.length - 1)).to_a

        # A chain of several consecutive sharp corners doesn't fully settle
        # with a single sweep direction repeated every pass -- relaxing
        # point i changes the angle its already-visited neighbor sees, but
        # a forward-only sweep never revisits it in the same pass. Reversing
        # direction each pass (Gauss-Seidel-style) lets information
        # propagate both ways along the chain. Stops once a full pass moves
        # every point less than a fraction of a unit (fully converged for
        # any diagram at this scale) rather than trusting a fixed pass
        # count to always be enough.
        ANGLE_RELAXATION_PASSES.times do |pass|
          order = pass.odd? ? indices.reverse : indices
          max_move = 0.0

          order.each do |i|
            before = relaxed[i]
            relaxed[i] = relax_corner(relaxed[i - 1], relaxed[i], relaxed[i + 1], max_turn_degrees)
            max_move = [max_move, point_distance(before, relaxed[i])].max
          end

          break if max_move < 0.05
        end

        relaxed
      end

      def relax_corner(a, b, c, max_turn_degrees)
        return b if turn_angle_degrees(a, b, c) <= max_turn_degrees

        midpoint = [(a[0] + c[0]) / 2.0, (a[1] + c[1]) / 2.0]
        lo = 0.0
        hi = 1.0

        20.times do
          t = (lo + hi) / 2.0
          candidate = [b[0] + ((midpoint[0] - b[0]) * t), b[1] + ((midpoint[1] - b[1]) * t)]
          turn_angle_degrees(a, candidate, c) > max_turn_degrees ? lo = t : hi = t
        end

        [b[0] + ((midpoint[0] - b[0]) * hi), b[1] + ((midpoint[1] - b[1]) * hi)]
      end

      # The angle between the incoming direction (a->b) and the outgoing
      # direction (b->c): 0 for a straight continuation, up to 180 for a
      # full reversal.
      def turn_angle_degrees(a, b, c)
        v1 = [b[0] - a[0], b[1] - a[1]]
        v2 = [c[0] - b[0], c[1] - b[1]]
        len1 = Math.hypot(*v1)
        len2 = Math.hypot(*v2)
        return 0.0 if len1.zero? || len2.zero?

        cos_angle = (((v1[0] * v2[0]) + (v1[1] * v2[1])) / (len1 * len2)).clamp(-1.0, 1.0)
        Math.acos(cos_angle) * 180.0 / Math::PI
      end
    end
  end
end
