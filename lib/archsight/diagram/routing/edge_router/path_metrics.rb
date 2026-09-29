# frozen_string_literal: true

require_relative "../../support/geometry"

module Archsight
  module Diagram
    module EdgeRouter
      # Pure segment/box geometry predicates and measurements used to score
      # a candidate path -- crossing counts and collinear-overlap length
      # against sibling paths (plain length itself is `Geometry.path_length`,
      # shared with the rest of the codebase).
      module PathMetrics
        module_function

        EDGE_EPSILON = 0.5

        def close?(v1, v2)
          (v1 - v2).abs <= EDGE_EPSILON
        end

        # Total length `path` spends running collinearly along any segment
        # of any path in `sibling_paths` -- summed over every segment pair,
        # one from each side.
        #
        # `nearby_paths` only ever drops a sibling whose bounding box can't
        # possibly hold a `close?`-collinear match to any of `path`'s own
        # segments -- it's padded by `EDGE_EPSILON` for exactly that reason:
        # `collinear_overlap` treats two segments up to `EDGE_EPSILON` apart
        # as the same line, so a sibling within that tolerance but just
        # outside `path`'s raw bounding box must still survive the filter.
        def overlap_length(path, sibling_paths)
          return 0.0 if sibling_paths.empty?

          relevant = nearby_paths(path, sibling_paths, margin: EDGE_EPSILON)
          return 0.0 if relevant.empty?

          path.each_cons(2).sum do |a1, a2|
            relevant.sum do |other|
              other.each_cons(2).sum { |b1, b2| collinear_overlap(a1, a2, b1, b2) }
            end
          end
        end

        # Whether `path` runs collinearly along any of `sibling_paths` at
        # all -- `overlap_length(path, sibling_paths).positive?`, but
        # stopping at the first overlapping segment pair instead of summing
        # them all. `boxes` are the siblings' `bounding_box`es when the caller
        # asks about many paths against the same siblings (so each sibling's is
        # computed once, not once per question); `skip` is an index into
        # `sibling_paths` to leave out (the path's own slot).
        def overlaps?(path, sibling_paths, boxes: sibling_paths.map { |other| bounding_box(other) }, skip: nil)
          lo_x, hi_x, lo_y, hi_y = bounding_box(path)

          sibling_paths.each_with_index.any? do |other, i|
            next false if i == skip

            olo_x, ohi_x, olo_y, ohi_y = boxes[i]
            next false unless olo_x - EDGE_EPSILON <= hi_x && ohi_x + EDGE_EPSILON >= lo_x &&
                              olo_y - EDGE_EPSILON <= hi_y && ohi_y + EDGE_EPSILON >= lo_y

            path.each_cons(2).any? do |a1, a2|
              other.each_cons(2).any? { |b1, b2| collinear_overlap(a1, a2, b1, b2).positive? }
            end
          end
        end

        # How much of segment (a1, a2) overlaps segment (b1, b2), when
        # they're collinear (both vertical at the same x, or both horizontal
        # at the same y) -- 0 if they merely cross at a point, run along
        # different lines, or don't overlap at all.
        def collinear_overlap(a1, a2, b1, b2)
          if close?(a1[0], a2[0]) && close?(b1[0], b2[0]) && close?(a1[0], b1[0])
            interval_overlap(a1[1], a2[1], b1[1], b2[1])
          elsif close?(a1[1], a2[1]) && close?(b1[1], b2[1]) && close?(a1[1], b1[1])
            interval_overlap(a1[0], a2[0], b1[0], b2[0])
          else
            0.0
          end
        end

        def interval_overlap(a1, a2, b1, b2)
          lo = [[a1, a2].min, [b1, b2].min].max
          hi = [[a1, a2].max, [b1, b2].max].min
          [hi - lo, 0.0].max
        end

        # How many segment pairs (one from `path`, one from each sibling
        # path) properly cross -- distinct from `overlap_length`, which only
        # measures segments running *along* each other.
        #
        # Unlike `overlap_length`'s `close?` tolerance, a true crossing is
        # an exact geometric fact -- two segments can only intersect at a
        # point that lies on both, so their bounding boxes must overlap; no
        # epsilon padding is needed for `nearby_paths` here (`segments_cross?`
        # already has its own much smaller `1e-6` tolerance, well under
        # floating-point noise at this scale).
        def crossing_edges_count(path, sibling_paths)
          return 0 if sibling_paths.empty?

          relevant = nearby_paths(path, sibling_paths, margin: 0.0)
          return 0 if relevant.empty?

          path.each_cons(2).sum do |a1, a2|
            relevant.sum do |other|
              other.each_cons(2).count { |b1, b2| segments_cross?(a1, a2, b1, b2) }
            end
          end
        end

        def nearby_paths(path, sibling_paths, margin:)
          lo_x, hi_x, lo_y, hi_y = bounding_box(path)

          sibling_paths.select do |other|
            olo_x, ohi_x, olo_y, ohi_y = bounding_box(other)
            olo_x - margin <= hi_x && ohi_x + margin >= lo_x && olo_y - margin <= hi_y && ohi_y + margin >= lo_y
          end
        end

        # True only when segments (a1, a2) and (b1, b2) intersect at a point
        # strictly inside *both* -- parallel/collinear segments (0 or
        # infinite intersections) are never a "crossing" here, that's
        # `collinear_overlap`'s domain, and an intersection right at (or
        # very near) either segment's own endpoint doesn't count either,
        # since that's just two edges legitimately meeting close together
        # near a shared box, not a stray crossing through the middle of
        # either line.
        def segments_cross?(a1, a2, b1, b2)
          x1, y1 = a1
          x2, y2 = a2
          x3, y3 = b1
          x4, y4 = b2

          denominator = ((x1 - x2) * (y3 - y4)) - ((y1 - y2) * (x3 - x4))
          return false if denominator.abs < 1e-9

          t = (((x1 - x3) * (y3 - y4)) - ((y1 - y3) * (x3 - x4))) / denominator
          u = (((x1 - x3) * (y1 - y2)) - ((y1 - y3) * (x1 - x2))) / denominator

          t > 1e-6 && t < 1.0 - 1e-6 && u > 1e-6 && u < 1.0 - 1e-6
        end

        # How many (segment, obstacle) pairs a path draws through -- the
        # "amount of visual clutter" a candidate causes, so `best_path` can
        # prefer the least-cluttered one instead of just the first
        # obstacle-free one it finds (and still pick the *least bad* option
        # when nothing is fully clear).
        #
        # Every point of `points` lies within the path's own bounding box, so
        # a box outside it can't be crossed either -- any point
        # `segment_crosses_box?` would call a crossing has to be inside the
        # box too, meaning the two boxes would overlap. Pre-filtering to only
        # the (usually far fewer) obstacles that do overlap it is exact, not
        # a heuristic: it only ever removes obstacles `segment_crosses_box?`
        # would have rejected anyway, before paying for that check.
        #
        # The overlap test must stay non-strict (`<=`/`>=`, not `<`/`>`):
        # `segment_crosses_box?` counts a segment that runs exactly along one
        # of the box's own edges (its perpendicular delta is 0, and its
        # coordinate on that axis exactly equals the box's edge) as a
        # crossing -- not just strictly-interior ones -- so a box merely
        # touching the path's bounding box can still register a crossing and
        # must not be filtered out.
        def crossing_count(points, obstacles)
          return 0 if obstacles.empty?

          relevant = nearby_obstacles(points, obstacles)
          return 0 if relevant.empty?

          # The same bounding-box lemma applies per segment, not just once
          # for the whole path -- a multi-segment candidate's overall span
          # (a mid-jog, a bridge, a dataflow hop) is often much bigger than
          # any single segment's own box, so narrowing `relevant` again to
          # each segment's own bounding box (still non-strict, same reason
          # as above) skips a further, often large, share of the
          # already-filtered obstacles before the Liang-Barsky test.
          points.each_cons(2).sum do |(x1, y1), (x2, y2)|
            lo_x, hi_x = [x1, x2].minmax
            lo_y, hi_y = [y1, y2].minmax

            relevant.count do |box|
              box.left <= hi_x && box.right >= lo_x && box.top <= hi_y && box.bottom >= lo_y &&
                segment_crosses_box?(x1, y1, x2, y2, box)
            end
          end
        end

        # A box shrunk by `EDGE_EPSILON` on every side -- see `enters_interior?`.
        Interior = Struct.new(:left, :right, :top, :bottom)

        # Whether `points` runs through `box`'s own interior anywhere, rather
        # than just touching its boundary -- the way every path touches the
        # two boxes it connects, at its own endpoints. Tested against the box
        # shrunk by `EDGE_EPSILON`, so a segment that starts on (or runs
        # along) the box's edge and heads away from it never counts.
        def enters_interior?(points, box)
          inner = Interior.new(box.left + EDGE_EPSILON, box.right - EDGE_EPSILON, box.top + EDGE_EPSILON, box.bottom - EDGE_EPSILON)
          points.each_cons(2).any? { |(x1, y1), (x2, y2)| segment_crosses_box?(x1, y1, x2, y2, inner) }
        end

        def nearby_obstacles(points, obstacles)
          lo_x, hi_x, lo_y, hi_y = bounding_box(points)

          obstacles.select { |box| box.left <= hi_x && box.right >= lo_x && box.top <= hi_y && box.bottom >= lo_y }
        end

        def bounding_box(points)
          xs = points.map { |p| p[0] }
          ys = points.map { |p| p[1] }
          lo_x, hi_x = xs.minmax
          lo_y, hi_y = ys.minmax
          [lo_x, hi_x, lo_y, hi_y]
        end

        # General segment-vs-rectangle intersection (Liang-Barsky line
        # clipping): works for `StraightPath`'s genuinely diagonal segments
        # as well as `OrthogonalPath`'s axis-aligned ones, unlike a simpler
        # check that only handles the latter. True only if the segment's
        # *interior* passes through `box` -- merely touching its boundary
        # (e.g. a segment that legitimately terminates exactly on a box's
        # edge) doesn't count.
        def segment_crosses_box?(x1, y1, x2, y2, box)
          dx = x2 - x1
          dy = y2 - y1
          t0 = 0.0
          t1 = 1.0
          p = [-dx, dx, -dy, dy]
          q = [x1 - box.left, box.right - x1, y1 - box.top, box.bottom - y1]

          4.times do |i|
            if p[i].zero?
              return false if q[i].negative?
            else
              t = q[i] / p[i].to_f
              if p[i].negative?
                t0 = t if t > t0
              elsif t < t1
                t1 = t
              end
              return false if t0 > t1
            end
          end

          true
        end
      end
    end
  end
end
