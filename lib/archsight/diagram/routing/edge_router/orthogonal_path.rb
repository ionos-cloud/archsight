# frozen_string_literal: true

require_relative "bridge_path"

module Archsight
  module Diagram
    module EdgeRouter
      # The single-turn/mid-jog candidate family: an axis-aligned route
      # bent once or twice between `a` and `b`'s own coordinates, plus
      # `BridgePath`'s loop-around routes for when nothing in-between
      # clears an obstacle.
      module OrthogonalPath
        # Where a two-turn mid-jog bends, as a fraction of the way from `a`
        # to `b` -- tried in this order (centered first, as the preferred
        # tie-break when several splits are equally clear of obstacles) so
        # an off-center jog is only picked when it actually avoids something
        # the centered one doesn't.
        MID_JOG_RATIOS = [0.5, 0.3, 0.7, 0.2, 0.8, 0.4, 0.6].freeze

        # Where a single turn's second run enters `b`, as a fraction along
        # the facing side of `b` -- centered first, then off-center entries
        # nearer either end. Turning nearer `a` can clear a neighbour that a
        # run dropping at `b`'s far-off center would cut through, without
        # resorting to a two-turn mid-jog.
        SINGLE_TURN_RATIOS = [0.5, 0.1, 0.9].freeze

        # How far a single turn's exit may also move off `a`'s center, away
        # from `b`, as a fraction of `a`'s extent: a source whose center
        # lies just past `b`'s side would otherwise turn right along that
        # side, in a stub too short to read (see `EdgeRouter::MIN_END_LEG`).
        # Only offered for such a source: anywhere else the centered exit
        # stays the only one.
        EXIT_SHIFT = 0.25

        # A single turn entering the target off its center, remembering by
        # how far. Entering nearer the source is always exactly that much
        # shorter, so `EdgeRouter.score_candidates` charges it back: the
        # centered entry then wins every tie, and an off-center one only
        # when it draws over fewer boxes or runs clear of a sibling's line.
        class OffCenterPath < Array
          attr_reader :entry_offset

          def initialize(points, entry_offset)
            super(points)
            @entry_offset = entry_offset
          end
        end

        module_function

        # Every orthogonal path worth considering between `a` and `b`: up to
        # two single-turn candidates (see `single_turn_horizontal_first`/
        # `single_turn_vertical_first` — nil, and dropped, when that
        # orientation would double back through one of the boxes), a
        # two-turn mid-jog in both orientations at each of `MID_JOG_RATIOS`
        # (likewise nil, and dropped, when `a` and `b` don't face each other
        # across a gap on that orientation's axis -- see `mid_jog_horizontal`),
        # and `BridgePath`'s loop-around routes for when an obstacle sits
        # squarely between `a` and `b` and no in-between bend clears it.
        # `EdgeRouter.route` picks among these by how many obstacles they
        # draw over; this list's order is purely the tie-break order for
        # when several candidates are equally clear (single turn, then a
        # mid-jog, then a bridge; dominant axis and centered splits first).
        def orthogonal_candidates(a, b, obstacles = [])
          dx = b.x - a.x
          dy = b.y - a.y

          # Centered exits first, the ones shifted away from `b` after them.
          exits = [0.0, EXIT_SHIFT]
          horizontal = exits.product(SINGLE_TURN_RATIOS).map { |shift, ratio| single_turn_horizontal_first(a, b, dx, dy, ratio, shift) }
          vertical = exits.product(SINGLE_TURN_RATIOS).map { |shift, ratio| single_turn_vertical_first(a, b, dx, dy, ratio, shift) }
          # Centered entries first (dominant axis leading), off-center ones after.
          singles = if dx.abs >= dy.abs
                      [horizontal.first, vertical.first, *horizontal.drop(1), *vertical.drop(1)]
                    else
                      [vertical.first, horizontal.first, *vertical.drop(1), *horizontal.drop(1)]
                    end.compact

          mid_jogs = MID_JOG_RATIOS.flat_map do |ratio|
            [mid_jog_horizontal(a, b, dx, dy, ratio), mid_jog_vertical(a, b, dx, dy, ratio)]
          end.compact
          candidates = singles + mid_jogs + BridgePath.bridge_candidates(a, b, obstacles)

          # `a` and `b` aren't in `obstacles` (a path always touches the two
          # boxes it connects), so nothing would penalize a candidate that
          # cuts back through one of them -- e.g. a bridge looping round
          # `a`'s far side, whose run into `b` crosses `a` itself. Dropped
          # outright instead, unless that leaves nothing at all (only
          # possible when `a` and `b` overlap, which a layout never produces
          # for two leaves).
          hits = Native.interior_hits(candidates, a, b) ||
                 candidates.map { |path| PathMetrics.enters_interior?(path, a) || PathMetrics.enters_interior?(path, b) }
          clear = candidates.reject.with_index { |_path, i| hits[i] }
          clear.empty? ? candidates : clear
        end

        # Route left-to-right (or right-to-left) with a vertical mid-jog,
        # bent at `ratio` of the way from `a` to `b` instead of always
        # dead-center -- a different split can clear an obstacle a centered
        # jog would cut through.
        #
        # Only safe when there's an actual horizontal gap between `a`'s and
        # `b`'s facing sides: when their x-extents overlap (e.g. one box
        # stacked above the other), "the side facing `b`" is on the far side
        # of `b`'s own edge, so the exit/entry runs would cut straight back
        # through both boxes -- nil then, and some other candidate (a
        # vertical mid-jog, a bridge, a straight line) has to do instead.
        def mid_jog_horizontal(a, b, dx, _dy, ratio = 0.5)
          return nil unless dx.positive? ? a.right < b.left : b.right < a.left

          start = { x: dx.positive? ? a.right : a.left, y: a.y }
          finish = { x: dx.positive? ? b.left : b.right, y: b.y }
          mid_x = start[:x] + ((finish[:x] - start[:x]) * ratio)
          [[start[:x], start[:y]], [mid_x, start[:y]], [mid_x, finish[:y]], [finish[:x], finish[:y]]]
        end

        # The transpose of `mid_jog_horizontal`: top-to-bottom (or
        # bottom-to-top) with a horizontal mid-jog bent at `ratio` -- nil
        # unless there's a vertical gap between the two facing sides.
        def mid_jog_vertical(a, b, _dx, dy, ratio = 0.5)
          return nil unless dy.positive? ? a.bottom < b.top : b.bottom < a.top

          start = { x: a.x, y: dy.positive? ? a.bottom : a.top }
          finish = { x: b.x, y: dy.positive? ? b.top : b.bottom }
          mid_y = start[:y] + ((finish[:y] - start[:y]) * ratio)
          [[start[:x], start[:y]], [start[:x], mid_y], [finish[:x], mid_y], [finish[:x], finish[:y]]]
        end

        # Exit `a` from whichever side (left/right) faces `b`, corner at
        # `(entry_x, a.y)` -- `entry_x` being `b`'s center, or `ratio` of the
        # way along `b`'s width (see `SINGLE_TURN_RATIOS`) -- then straight
        # into `b`'s facing top/bottom edge.
        # Safe exactly when: (1) the corner truly lies beyond `a` in `b`'s
        # direction, so the exit run can't double back through `a`, which
        # also guarantees the corner-to-entry run (at x = entry_x) clears `a`
        # entirely; and (2) `a`'s own y sits outside `b`'s vertical span, so
        # the exit-to-corner run (at y = a.y) clears `b` entirely.
        # `exit_shift` moves the exit that fraction of `a`'s height away from
        # `b` (see `EXIT_SHIFT`).
        def single_turn_horizontal_first(a, b, dx, dy, ratio = 0.5, exit_shift = 0.0)
          return nil if dx.zero?

          corner_x = ratio == 0.5 ? b.x : b.left + (b.width * ratio)
          return nil if dx.positive? ? (corner_x <= a.right) : (corner_x >= a.left)

          return nil unless exit_shift.zero? || short_run?(a.y, b.top, b.bottom)

          exit_y = a.y - ((dy <=> 0) * a.height * exit_shift)
          return nil unless exit_y < b.top || exit_y > b.bottom

          exit_point = [dx.positive? ? a.right : a.left, exit_y]
          corner = [corner_x, exit_y]
          entry_point = [corner_x, dy.positive? ? b.top : b.bottom]
          off_center(ratio, corner_x - b.x, [exit_point, corner, entry_point])
        end

        # The transpose of `single_turn_horizontal_first`: exit `a` from
        # whichever top/bottom edge faces `b`, corner at `(a.x, b.y)`, then
        # straight into `b`'s facing left/right edge.
        def single_turn_vertical_first(a, b, dx, dy, ratio = 0.5, exit_shift = 0.0)
          return nil if dy.zero?

          corner_y = ratio == 0.5 ? b.y : b.top + (b.height * ratio)
          return nil if dy.positive? ? (corner_y <= a.bottom) : (corner_y >= a.top)

          return nil unless exit_shift.zero? || short_run?(a.x, b.left, b.right)

          exit_x = a.x - ((dx <=> 0) * a.width * exit_shift)
          return nil unless exit_x < b.left || exit_x > b.right

          exit_point = [exit_x, dy.positive? ? a.bottom : a.top]
          corner = [exit_x, corner_y]
          entry_point = [dx.positive? ? b.left : b.right, corner_y]
          off_center(ratio, corner_y - b.y, [exit_point, corner, entry_point])
        end

        # Whether a centered exit at `coord` lies just outside `b`'s span
        # `low..high`, so its run into `b` would be shorter than
        # `EdgeRouter::MIN_END_LEG`.
        def short_run?(coord, low, high)
          gap = coord < low ? low - coord : coord - high
          gap.positive? && gap < EdgeRouter::MIN_END_LEG
        end

        def off_center(ratio, offset, points)
          ratio == SINGLE_TURN_RATIOS.first ? points : OffCenterPath.new(points, offset.abs)
        end
      end
    end
  end
end
