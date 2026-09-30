# frozen_string_literal: true

require_relative "path_metrics"
require_relative "../../native"

module Archsight
  module Diagram
    module EdgeRouter
      # The loop-around candidate family: "U"-shaped routes that leave `a`
      # on one of its 4 sides, jog perpendicular out past every relevant
      # box's extent on that axis, slide across, then jog back in to `b`'s
      # matching side. Needed whenever an obstacle sits squarely between
      # `a` and `b` at a shared axis level that no in-between bend
      # (`OrthogonalPath`'s mid-jog) can dodge, since a mid-jog only ever
      # bends *between* the two boxes' own coordinates.
      module BridgePath
        # How far beyond `a`/`b`/the obstacles' own extent a bridge's loop
        # clears, so the loop doesn't run flush along an obstacle's edge.
        BRIDGE_MARGIN = 20.0
        # How far a bridge's first segment moves straight away from `a`
        # before it turns to run parallel to `a`'s own exit edge -- without
        # this, that parallel run starts flush against the box's own
        # boundary and reads as an extension of the box's outline rather
        # than a line leaving it. A real exit always starts perpendicular to
        # the edge it leaves from. This is a ceiling, not a fixed length --
        # see `stub_length`, which shrinks it when a neighboring box sits
        # close by in that same direction.
        BRIDGE_STUB = 20.0
        # `stub_length` never shrinks the stub below this, even when the gap
        # to a neighboring box is tight -- small enough to always fit, still
        # enough to read as a deliberate turn rather than no stub at all.
        MIN_BRIDGE_STUB = 6.0
        # Every bridge on the same side of the same obstacles loops at
        # exactly one level (`BRIDGE_MARGIN` out) -- so several edges that
        # all have to go around the whole diagram end up on one shared
        # line, and `EdgeRouting#refine_line_overlap!`'s overlap penalty has
        # nowhere to move them. An edge whose chosen bridge does overlap a
        # sibling gets `lane_variants` of it as extra candidates (see
        # `EdgeRouting#separate_bridge_lanes!`): up to `BRIDGE_LANES - 1`
        # further-out parallel lanes, this far apart. Generated only for
        # those few edges, never for every edge's candidate list.
        BRIDGE_LANE_SPACING = 8.0
        BRIDGE_LANES = 4
        # Two bridges into different boxes that share a center line (a
        # boundary and a box inside it) would still climb into their targets
        # along one shared line, whatever lane each loops on -- so each
        # variant also comes with its entry this far off-center. Always
        # *away* from the side the loop approaches from, so the shifted
        # entry is strictly longer and only wins when it sheds overlap.
        BRIDGE_ENTRY_OFFSET = 12.0

        module_function

        def bridge_candidates(a, b, obstacles)
          # Only obstacles that actually overlap the rectangle spanning `a`
          # and `b` could plausibly be "in the way" of a direct route
          # between them -- clearing against the *entire* diagram's extent
          # instead would pull the loop out to whatever's furthest away
          # (e.g. the top of the whole canvas), and that long a detour
          # usually crosses other, unrelated boxes along the way, losing to
          # simpler candidates despite fully clearing the one obstacle that
          # actually mattered.
          stubs, top, bottom, left, right = bridge_bounds(a, b, obstacles)

          horizontal = %i[left right].flat_map do |exit_side|
            exit_x = exit_side == :left ? a.left : a.right
            stub = stubs[exit_side]

            [
              bridge_path([exit_x, a.y], exit_side, stub, :y, top - BRIDGE_MARGIN, b, entry_side: :top),
              bridge_path([exit_x, a.y], exit_side, stub, :y, bottom + BRIDGE_MARGIN, b, entry_side: :bottom)
            ]
          end

          vertical = %i[top bottom].flat_map do |exit_side|
            exit_y = exit_side == :top ? a.top : a.bottom
            stub = stubs[exit_side]

            [
              bridge_path([a.x, exit_y], exit_side, stub, :x, left - BRIDGE_MARGIN, b, entry_side: :left),
              bridge_path([a.x, exit_y], exit_side, stub, :x, right + BRIDGE_MARGIN, b, entry_side: :right)
            ]
          end

          horizontal + vertical
        end

        # A `bridge_path` is the only candidate shape with five points
        # (exit, stub, the loop's two corners, entry) -- a straight line
        # has two, a single turn three, a mid-jog four.
        def bridge?(path) = path.length == 5

        # Alternatives to an already-chosen bridge `path` into `target`,
        # derived from its points alone: its loop run moved outward by each
        # further lane (`BRIDGE_LANE_SPACING` apart, `BRIDGE_LANES` in all),
        # plus each of those and `path` itself with its entry shifted off
        # `target`'s center (see `BRIDGE_ENTRY_OFFSET`). Every variant is
        # longer than `path`, so it's only ever picked to shed overlap.
        # Empty for anything that isn't a bridge.
        def lane_variants(path, target)
          return [] unless bridge?(path)

          # The stub runs perpendicular to the loop's line; the loop sits
          # at `path[2]`, and "outward" is the way the path went to reach it.
          loop_index = path[1][0] == path[2][0] ? 1 : 0
          outward = path[2][loop_index] <=> path[1][loop_index]
          return [] if outward.zero?

          lanes = (1...BRIDGE_LANES).map do |lane|
            offset = outward * lane * BRIDGE_LANE_SPACING
            path.each_with_index.map { |pt, i| [2, 3].include?(i) ? move(pt, loop_index, offset) : pt }
          end

          entry_index = 1 - loop_index
          extent = entry_index.zero? ? target.width : target.height
          lanes + ([path] + lanes).filter_map { |lane| shift_entry(lane, entry_index, extent) }
        end

        # `path` with its last two points -- the run along the loop's line
        # into the target, and the entry itself -- moved
        # `BRIDGE_ENTRY_OFFSET` along coordinate `index`, away from where the
        # loop comes from. Nil when the target's `extent` along that axis is
        # too small to take the offset.
        def shift_entry(path, index, extent)
          return nil if (extent / 2.0) - BRIDGE_ENTRY_OFFSET < MIN_BRIDGE_STUB

          delta = path[3][index] >= path[2][index] ? BRIDGE_ENTRY_OFFSET : -BRIDGE_ENTRY_OFFSET
          path[0..2] + path[3..].map { |pt| move(pt, index, delta) }
        end

        def move(point, index, delta)
          moved = point.dup
          moved[index] += delta
          moved
        end

        EXIT_SIDES = %i[left right top bottom].freeze

        # Every exit side's `stub_length`, plus the extent the loop has to
        # clear -- the outermost top/bottom/left/right of `a`, `b` and every
        # obstacle in between them (see `nearby_obstacles`). Both are full
        # scans over `obstacles`, done in one `Native.bridge_scan` call when
        # the native kernels are built.
        def bridge_bounds(a, b, obstacles)
          if (scan = Native.bridge_scan(a, b, obstacles))
            gaps = scan.first(4)
            stubs = EXIT_SIDES.zip(gaps).to_h { |side, gap| [side, gap.infinite? ? BRIDGE_STUB : stub_for_gap(gap)] }
            return [stubs, *scan.last(4)]
          end

          boxes = [a, b] + nearby_obstacles(a, b, obstacles)
          stubs = EXIT_SIDES.to_h { |side| [side, stub_length(a, side, obstacles)] }
          [stubs, boxes.map(&:top).min, boxes.map(&:bottom).max, boxes.map(&:left).min, boxes.map(&:right).max]
        end

        def stub_length(a, exit_side, obstacles)
          facing = obstacles.select { |o| facing_obstacle?(a, exit_side, o) }
          return BRIDGE_STUB if facing.empty?

          stub_for_gap(facing.map { |o| gap_to(a, exit_side, o) }.min)
        end

        def stub_for_gap(gap)
          [[gap / 2.0, MIN_BRIDGE_STUB].max, BRIDGE_STUB].min
        end

        def facing_obstacle?(a, exit_side, o)
          case exit_side
          when :left then o.right <= a.left && a.overlaps_y?(o)
          when :right then o.left >= a.right && a.overlaps_y?(o)
          when :top then o.bottom <= a.top && a.overlaps_x?(o)
          when :bottom then o.top >= a.bottom && a.overlaps_x?(o)
          end
        end

        def gap_to(a, exit_side, o)
          case exit_side
          when :left then a.left - o.right
          when :right then o.left - a.right
          when :top then a.top - o.bottom
          when :bottom then o.top - a.bottom
          end
        end

        # Builds one bridge candidate: `exit_point` -> a short perpendicular
        # stub straight away from `a` (see `stub_length`) -> (jog to
        # `loop_coord` on `loop_axis`) -> (slide across to align with `b`)
        # -> `b`'s `entry_side`. Without the stub, the loop's first segment
        # would start flush against `a`'s own `exit_side` edge and run
        # parallel to it -- reading as an extension of the box's outline
        # rather than a line leaving it; the stub guarantees the path always
        # leaves `a` perpendicular to the side it exits from, the same way
        # every other candidate shape already does.
        def bridge_path(exit_point, exit_side, stub, loop_axis, loop_coord, b, entry_side:)
          if loop_axis == :y
            stub_x = exit_side == :left ? exit_point[0] - stub : exit_point[0] + stub
            stub_point = [stub_x, exit_point[1]]
            entry_point = [b.x, entry_side == :top ? b.top : b.bottom]
            [exit_point, stub_point, [stub_x, loop_coord], [b.x, loop_coord], entry_point]
          else
            stub_y = exit_side == :top ? exit_point[1] - stub : exit_point[1] + stub
            stub_point = [exit_point[0], stub_y]
            entry_point = [entry_side == :left ? b.left : b.right, b.y]
            [exit_point, stub_point, [loop_coord, stub_y], [loop_coord, b.y], entry_point]
          end
        end

        # Obstacles that overlap the rectangle spanning `a` and `b` on both
        # axes -- i.e. could plausibly sit between them -- rather than
        # anything elsewhere in the diagram. An inline AABB test: the
        # "rectangle spanning a and b" is a synthesized span, not an actual
        # `Layout::Box`, and `EdgeRouter` must not depend on `Layout` to
        # construct one (the dependency runs the other way).
        def nearby_obstacles(a, b, obstacles)
          lo_x = [a.left, b.left].min
          hi_x = [a.right, b.right].max
          lo_y = [a.top, b.top].min
          hi_y = [a.bottom, b.bottom].max

          obstacles.select { |o| o.left < hi_x && o.right > lo_x && o.top < hi_y && o.bottom > lo_y }
        end
      end
    end
  end
end
