# frozen_string_literal: true

require_relative "edge_router"
require_relative "../layout"
require_relative "obstacle_map"

module Archsight
  module Diagram
    # Obstacle-aware routing, line-overlap refinement, and port-splitting
    # for plain (individually-routed) edges -- the ones
    # `Renderer#implements_tree_groups` didn't fold into an
    # `Renderer::ImplementsTreeRenderer` tree instead. A pipeline stage
    # between `Layout` (box positions) and `Renderer` (SVG markup): this
    # class computes *where* each edge's line goes; it never emits any
    # markup itself (see `Renderer::EdgeRenderer` for that).
    class EdgeRouting
      # One edge's computed route, plus the obstacle-avoidance context
      # needed to re-score/re-shift it later (`refine_line_overlap!`/
      # `assign_ports!`) without recomputing it from scratch:
      # `refine_line_overlap!`/`assign_ports!` replace `points` across
      # several passes, and `Renderer#render` reads `edge`/`points` back
      # out. `scored` -- this edge's candidate paths plus their `crossing`/`length`
      # scores (see `EdgeRouter.score_candidates`) -- is cached here too:
      # it depends only on `obstacles`, which never changes for this edge
      # across `compute_paths` and every `refine_line_overlap!` round, so
      # computing it once and reusing it avoids rebuilding identical
      # candidate geometry and rescoring it from scratch on every round.
      RoutedEdge = Struct.new(:edge, :points, :from_box, :to_box, :obstacles, :scored, keyword_init: true)

      # One edge-endpoint's candidacy for a shared box-side port slot (see
      # `assign_ports!`) -- purely internal, never read outside
      # `apply_port_slots`.
      # `approach` is where the line arrives from, along the side's own axis:
      # the neighbouring point's coordinate -- the far endpoint for a
      # straight edge, the perpendicular final run for an orthogonal one.
      # `order` is what the side's members are sorted by: where the line is
      # once it's `PORT_ORDER_PROBE` out from the side (see `order_key`);
      # `far` -- where it finally ends up, its far endpoint -- breaks ties
      # between lines still running together at that depth.
      PortMember = Struct.new(:edge_path, :role, :box, :axis, :original, :approach, :order, :far, keyword_init: true)

      # How many times `refine_line_overlap!` sweeps every edge. Each round
      # re-scores every edge against every other edge's *current* path, in
      # declaration order -- one round alone means an early edge only ever
      # sees later ones' raw, unrefined pass-1 positions, so it can't react
      # to a route they only settle into during their own turn. A second
      # round lets it react to what they actually became; not iterated to
      # full convergence, just enough for information to flow both
      # directions through the edge list once.
      LINE_OVERLAP_REFINEMENT_ROUNDS = 2

      # How far each end slot is inset from the box's own corners, so a
      # line at the very first or last slot doesn't exit right at a
      # rounded corner.
      PORT_EDGE_MARGIN = 10.0

      # The least distance two endpoints on the same box side are kept
      # apart (see `apply_port_slots`) -- closer than this and they read as
      # one shared connection. Capped at one slot's width on a side too
      # crowded to fit it, so every endpoint still gets a slot of its own
      # (evenly spaced, rather than bunched against a neighbour's).
      PORT_MIN_GAP = 8.0

      # How far out from a box side `assign_ports!` looks to decide the
      # order its lines sit in along that side (see `order_key`) -- past a
      # bridge's stub (`BridgePath::BRIDGE_STUB`), so a stub's short
      # perpendicular run doesn't make two lines heading opposite ways look
      # alike, but close enough that a turn far away (a long run in, then a
      # bend) doesn't count either.
      PORT_ORDER_PROBE = 2 * EdgeRouter::BridgePath::BRIDGE_STUB
      # Two lines whose `order_key`s are closer than this are still running
      # (nearly) together at `PORT_ORDER_PROBE` -- e.g. both level with the
      # box's own center -- so they're ordered by where each one ends up
      # instead (see `port_order`).
      PORT_ORDER_TOLERANCE = PORT_MIN_GAP / 2.0

      # `obstacle_map` can be shared with `DataflowRouting` over the same boxes.
      def initialize(graph, boxes, obstacle_map: ObstacleMap.new(boxes))
        @graph = graph
        @boxes = boxes
        @obstacle_map = obstacle_map
      end

      # Every edge's route, computed up front (rather than immediately
      # rendered one at a time) so `assign_ports!` can see every edge
      # attached to a box before deciding whether any of its sides need to
      # split into multiple attachment points.
      def compute_paths(edges)
        edges.map do |edge|
          from = positioned(edge.from)
          to = positioned(edge.to)
          obstacles = @obstacle_map.excluding(edge.from, edge.to)
          candidates = EdgeRouter.candidate_paths(from.box, to.box, edge.attrs["style"],
                                                  from_shape: from.shape, to_shape: to.shape, obstacles: obstacles)
          scored = EdgeRouter.score_candidates(candidates, obstacles)
          points = EdgeRouter.select_best(scored, sibling_paths: [])
          RoutedEdge.new(edge: edge, points: points, from_box: from.box, to_box: to.box, obstacles: obstacles, scored: scored)
        end
      end

      # `compute_paths` routes every edge in isolation, with no idea where
      # any other edge's line ends up -- so two routing choices that are
      # otherwise equally good can differ only in whether one happens to
      # run right along, or cross, a sibling edge's line, and nothing
      # steers it away from that. This re-picks each edge's route (from
      # the same candidates `compute_paths` had available), this time
      # scoring against every other edge's *current* path too (see
      # `EdgeRouter::LINE_OVERLAP_PENALTY`/`LINE_CROSSING_PENALTY`).
      #
      # `select_best` is a pure function of an edge's (fixed, cached)
      # `scored` candidates and its siblings' *current* points -- so a round
      # that changes no edge's points leaves every edge's siblings exactly
      # as the next round would see them too, meaning the next round is
      # guaranteed to also change nothing. Stopping as soon as a round is a
      # no-op is exact, not an early cutoff: in practice most diagrams
      # settle within the first round or two anyway.
      #
      # `Native.refine_line_overlap!` runs this whole sweep in C when the
      # native kernels are built (it's quadratic in the edge count, and by
      # far the most expensive part of rendering a large diagram).
      def refine_line_overlap!(edge_paths)
        return if Native.refine_line_overlap!(edge_paths, LINE_OVERLAP_REFINEMENT_ROUNDS)

        LINE_OVERLAP_REFINEMENT_ROUNDS.times do
          break unless refine_line_overlap_once!(edge_paths)
        end
      end

      # `refine_line_overlap!` can only choose among each edge's own
      # candidates, and every bridge around the same obstacles loops on the
      # same line -- so edges that all have to go around the diagram stay
      # piled onto it, with nowhere to move. For just the edges whose chosen
      # bridge still overlaps a sibling, this adds that bridge's
      # `BridgePath.lane_variants` (outer parallel lanes, off-center
      # entries) to its candidates and re-runs the sweep. Done lazily
      # rather than giving every edge every lane up front: bridges are
      # rare, and overlapping ones rarer, so a diagram without the problem
      # pays for one overlap check per bridge and nothing more.
      def separate_bridge_lanes!(edge_paths)
        extended = false

        edge_paths.each do |ep|
          next unless EdgeRouter::BridgePath.bridge?(ep.points)

          siblings = edge_paths.filter_map { |other| other.points unless other.equal?(ep) }
          next unless EdgeRouter::PathMetrics.overlap_length(ep.points, siblings).positive?

          variants = EdgeRouter::BridgePath.lane_variants(ep.points, ep.to_box)
          next if variants.empty?

          ep.scored += EdgeRouter.score_candidates(variants, ep.obstacles)
          extended = true
        end

        refine_line_overlap!(edge_paths) if extended
      end

      # A box's default attachment point (the box's own center coordinate
      # on the relevant axis) reads fine for a single edge, but when
      # several edges attach to the same side of the same box they'd all
      # land on that one point, merging together right at the boundary
      # instead of reading as distinct connections. For every (box, side)
      # touched by more than one edge endpoint -- pooling the box's
      # outgoing and incoming edges together, since both are just "a line
      # touching this side" -- this splits that side into as many equal
      # sections as it has attached edges and moves each endpoint to the
      # center of its own section, via `EdgeRouter::Attachment.shift_attachment`.
      # Sides with only one attached edge are left exactly as routed.
      def assign_ports!(edge_paths)
        groups = Hash.new { |h, k| h[k] = [] }

        edge_paths.each do |ep|
          add_port_member(groups, ep, :start, ep.from_box, ep.points.first)
          add_port_member(groups, ep, :end, ep.to_box, ep.points.last)
        end

        groups.each_value { |members| apply_port_slots(members) if members.length > 1 }
      end

      private

      def positioned(node)
        Layout::PositionedNode.new(node, @boxes[node.id])
      end

      # Returns whether any edge's `points` actually changed this round.
      def refine_line_overlap_once!(edge_paths)
        changed = false

        edge_paths.each do |ep|
          siblings = edge_paths.filter_map { |other| other.points unless other.equal?(ep) }
          new_points = EdgeRouter.select_best(ep.scored, sibling_paths: siblings)
          changed = true if new_points != ep.points
          ep.points = new_points
        end

        changed
      end

      def add_port_member(groups, edge_path, role, box, point)
        side = box.side_of(point)
        return unless side

        axis = %i[left right].include?(side) ? :y : :x
        coord_index = axis == :y ? 1 : 0
        onward = role == :start ? edge_path.points : edge_path.points.reverse

        groups[[box.object_id, side]] << PortMember.new(
          edge_path: edge_path, role: role, box: box, axis: axis,
          original: point[coord_index], approach: onward[1][coord_index], order: order_key(onward, side, coord_index),
          far: onward.last[coord_index]
        )
      end

      # The coordinate along `side` at which the path `onward` (starting at
      # its endpoint on that side) first gets `PORT_ORDER_PROBE` away from
      # it -- or its far end's, if it never does (a short hop, or a stub
      # that turns to run alongside the box). Two lines sorted by this don't
      # cross each other on the way in, whether each arrives slanted,
      # perpendicular, or out of a stub that turns straight away.
      def order_key(onward, side, coord_index)
        depth_index = 1 - coord_index
        outward = %i[right bottom].include?(side) ? 1 : -1
        base = onward.first[depth_index]
        depth = ->(pt) { (pt[depth_index] - base) * outward }

        onward.each_cons(2) do |p, q|
          next unless depth.call(q) >= PORT_ORDER_PROBE

          t = (PORT_ORDER_PROBE - depth.call(p)) / (depth.call(q) - depth.call(p))
          return p[coord_index] + (t * (q[coord_index] - p[coord_index]))
        end
        onward.last[coord_index]
      end

      # Each member (sorted by `order`, so lines don't cross each other on
      # the way in) gets its own even band of the side, and *within* that
      # band lands exactly on its `approach` coordinate when it can -- which
      # keeps an edge that was already lined up with its target straight,
      # instead of skewing it to the band's bare center.
      #
      # A shift that's fine in isolation can still drag a shared interior
      # point (e.g. a single-turn route's corner, tied to this same box's
      # port) into an obstacle the original, obstacle-aware route
      # deliberately avoided, so a position is only taken if it doesn't make
      # that edge's own route worse (see `shift_for`). Members are then
      # placed most-constrained first -- one with no such position anywhere
      # in its band stays where it was routed, then every `flexible?` one
      # after the rest (moving it just slides its own perpendicular run,
      # while moving a straight line skews it), fewest options first --
      # and every later one keeps `PORT_MIN_GAP` clear of everything
      # already placed, rather than being slotted as if its neighbour had
      # moved and landing right on top of it.
      def apply_port_slots(members)
        box = members.first.box
        low, high = members.first.axis == :y ? [box.top, box.bottom] : [box.left, box.right]
        n = members.length
        margin = [PORT_EDGE_MARGIN, (high - low) / (n * 2.0)].min
        low += margin
        high -= margin
        band_width = (high - low) / n.to_f
        # Less a hair, so band-centre-to-band-centre (exactly one band
        # apart) still passes despite float rounding.
        min_gap = [PORT_MIN_GAP, band_width].min - 1e-6

        placements = members.sort { |m, n| port_order(m, n) }.each_with_index.map do |member, i|
          band_low = low + (band_width * i)
          [member, band_shifts(member, band_low, band_low + band_width, low, high)]
        end

        order = placements.each_with_index.sort_by do |(member, shifts), i|
          [shifts.empty? ? 0 : 1, flexible?(member) ? 1 : 0, shifts.length, i]
        end
        place_members(order.map(&:first), min_gap)
      end

      # Moves each `[member, shifts]` in turn to its first shift clear of
      # every endpoint already placed (see `apply_port_slots`).
      def place_members(placements, min_gap)
        taken = []
        moved = Set.new.compare_by_identity
        placements.each do |member, shifts|
          pos, points = shifts.find { |p, _| taken.all? { |t| (p - t).abs >= min_gap } } || shifts.first
          # Both ends of one line on this same side: `points` was shifted
          # from the line as routed, so it would undo the other end's move.
          points = shift_for(member, pos)&.last if points && moved.include?(member.edge_path)
          unless points
            taken << member.original
            next
          end

          taken << pos
          member.edge_path.points = points
          moved << member.edge_path
        end
      end

      def port_order(m, n)
        return m.order <=> n.order if (m.order - n.order).abs >= PORT_ORDER_TOLERANCE

        [m.far, m.approach] <=> [n.far, n.approach]
      end

      # Whether moving `member`'s endpoint keeps its route's shape: it
      # arrives perpendicular, along a run `EdgeRouter::Attachment.shift_attachment`
      # moves as a whole -- unlike a straight two-point line, whose far end
      # stays put, so it only ever tilts.
      def flexible?(member)
        member.edge_path.points.length > 2 && EdgeRouter::PathMetrics.close?(member.approach, member.original)
      end

      # Every acceptable `[pos, shifted points]` for `member` within its own
      # band, best first: straight in on its `approach`, then the band's
      # center, then either end -- except that a `flexible?` member, which
      # stays straight wherever it lands, prefers the center, so a side's
      # lines spread evenly across it instead of bunching up around
      # wherever they happened to be routed.
      #
      # A line that's already straight (a two-point run perpendicular to
      # the side) first tries to stay exactly where it is, anywhere along
      # the side and not just within its band: moving only its box end
      # would tilt it, and `place_members` already keeps it clear of every
      # endpoint placed before it.
      def band_shifts(member, band_low, band_high, side_low, side_high)
        straight = member.approach.clamp(band_low, band_high)
        center = (band_low + band_high) / 2.0
        preferred = flexible?(member) ? [center, straight] : [straight, center]
        keep = member.edge_path.points.length == 2 && EdgeRouter::PathMetrics.close?(member.approach, member.original) &&
               member.original.between?(side_low, side_high)
        positions = [*(member.original if keep), *preferred, band_low, band_high].uniq
        positions.filter_map { |pos| shift_for(member, pos) }
      end

      # `[pos, shifted points]` for moving `member`'s endpoint to `pos`, or
      # nil when that would make its route cross more obstacles than it
      # already does.
      def shift_for(member, pos)
        path = member.edge_path
        delta = pos - member.original
        return [pos, path.points] if delta.zero?

        shifted = EdgeRouter::Attachment.shift_attachment(path.points, member.axis, delta, at: member.role)
        return nil if EdgeRouter.crossing_count(shifted, path.obstacles) > EdgeRouter.crossing_count(path.points, path.obstacles)

        [pos, shifted]
      end
    end
  end
end
