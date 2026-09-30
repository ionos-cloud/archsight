# frozen_string_literal: true

require_relative "../support/geometry"

module Archsight
  module Diagram
    class Renderer
      # SVG `d`-string builders for a point list -- straight L-segments, or
      # (for a dataflow) a smooth centripetal Catmull-Rom curve. The pure
      # point-list math this builds on (length, point-at-fraction,
      # simplification, turn-angle limiting) is `Archsight::Diagram::Geometry`,
      # shared with the routing stages, which must never depend on
      # `Renderer`.
      module PathGeometry
        module_function

        def path_d_string(points, curve: false)
          curve && points.length > 2 ? smooth_path_d(points) : straight_path_d(points)
        end

        def straight_path_d(points)
          points.each_with_index.map { |(x, y), i| "#{i.zero? ? "M" : "L"} #{SvgFormat.fmt(x)} #{SvgFormat.fmt(y)}" }.join(" ")
        end

        # Centripetal parameterization (alpha = 0.5): the standard choice for
        # fitting a Catmull-Rom spline through unevenly-spaced points without
        # the loops/cusps a plain *uniform* spline (alpha = 0, tried first
        # here) produces right where points sit close together -- exactly
        # what a nudged intermediate hop's two through-points, or an
        # endpoint stub, are.
        CATMULL_ROM_ALPHA = 0.5

        # One cubic Bezier segment per pair of consecutive points, fit as a
        # centripetal Catmull-Rom spline through the *entire* `points` list
        # (every original waypoint -- box anchors, nudged through-points,
        # endpoint stubs -- stays exactly on the curve), with the missing
        # neighbor at either end of the list clamped to the segment's own
        # endpoint. Used only for a dataflow's line -- a plain edge/
        # implements-tree segment stays fully straight, matching the rest of
        # the diagram's architecture-diagram look.
        def smooth_path_d(points)
          d = "M #{SvgFormat.fmt(points[0][0])} #{SvgFormat.fmt(points[0][1])}"

          (0...(points.length - 1)).each do |i|
            p1 = points[i]
            p2 = points[i + 1]
            # A phantom neighbor *duplicating* the boundary point (distance
            # 0) is a degenerate knot spacing that `catmull_rom_bezier_controls`
            # falls back to a dead-straight segment for -- which is exactly
            # why the first/last segment (an endpoint stub included) rendered
            # as a rigid straight run instead of a curve. Reflecting the
            # adjacent real point through the boundary point instead gives a
            # legitimate phantom neighbor, so the curve's natural roundness
            # extends all the way to both true ends.
            p0 = i.zero? ? reflect_point(p1, p2) : points[i - 1]
            p3 = i + 2 < points.length ? points[i + 2] : reflect_point(p2, p1)

            b1, b2 = catmull_rom_bezier_controls(p0, p1, p2, p3)
            d << " C #{SvgFormat.fmt(b1[0])} #{SvgFormat.fmt(b1[1])} #{SvgFormat.fmt(b2[0])} #{SvgFormat.fmt(b2[1])} " \
                 "#{SvgFormat.fmt(p2[0])} #{SvgFormat.fmt(p2[1])}"
          end

          d
        end

        # The mirror of `other` through `pivot` -- used to synthesize a
        # legitimate (non-zero-distance) phantom neighbor just past either
        # end of the point list for `smooth_path_d`.
        def reflect_point(pivot, other)
          [(2 * pivot[0]) - other[0], (2 * pivot[1]) - other[1]]
        end

        # The two Bezier control points for the segment from `p1` to `p2`,
        # given its neighbors `p0`/`p3`, via centripetal Catmull-Rom: knot
        # spacing is each gap's distance^alpha (not a uniform 1), and each
        # endpoint's tangent is the chord through its two neighbors, scaled
        # to this segment's own knot spacing.
        def catmull_rom_bezier_controls(p0, p1, p2, p3)
          t0 = 0.0
          t1 = t0 + (Geometry.point_distance(p0, p1)**CATMULL_ROM_ALPHA)
          t2 = t1 + (Geometry.point_distance(p1, p2)**CATMULL_ROM_ALPHA)
          t3 = t2 + (Geometry.point_distance(p2, p3)**CATMULL_ROM_ALPHA)

          return [p1, p2] if t1 <= t0 || t2 <= t1 || t3 <= t2

          segment = t2 - t1
          m1 = [(p2[0] - p0[0]) / (t2 - t0) * segment, (p2[1] - p0[1]) / (t2 - t0) * segment]
          m2 = [(p3[0] - p1[0]) / (t3 - t1) * segment, (p3[1] - p1[1]) / (t3 - t1) * segment]

          [[p1[0] + (m1[0] / 3.0), p1[1] + (m1[1] / 3.0)], [p2[0] - (m2[0] / 3.0), p2[1] - (m2[1] / 3.0)]]
        end
      end
    end
  end
end
