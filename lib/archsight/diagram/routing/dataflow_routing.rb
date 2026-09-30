# frozen_string_literal: true

require_relative "edge_router"
require_relative "../layout"
require_relative "obstacle_map"
require_relative "../support/geometry"
require_relative "dataflow_routing/branch_label_policy"

module Archsight
  module Diagram
    # Dataflow hop-group expansion, box-nudging/stub/fork-reconciliation,
    # and routing. A dataflow is a distinct, always-visible, colored/
    # labeled illustrative overlay over existing nodes/edges -- every
    # hop-to-hop segment is routed with the same obstacle-avoiding
    # `EdgeRouter.route` a plain edge gets, then nudged/stubbed/smoothed so
    # the line visibly continues through each intermediate box instead of
    # just touching its edge. A pipeline stage between `Layout` and
    # `Renderer`: this class computes *where* each dataflow's line goes; it
    # never emits any markup itself (see `Renderer::DataflowRenderer` for
    # that).
    class DataflowRouting
      # One dataflow's (or, for a grouped dataflow, one trunk/branch
      # piece's) computed route. A `Struct` (not a plain Hash):
      # `reconcile_dataflow_forks!` mutates `points` in place, and
      # `Renderer#render`/`DataflowRenderer#render` read `dataflow`/
      # `points` back out -- both read equally well via `[:key]` (a
      # `Struct`'s own built-in accessor) or `.key`.
      DataflowRoute = Struct.new(:dataflow, :points, keyword_init: true)

      # How far an intermediate hop's junction point gets pushed into its
      # box's interior (perpendicular to whichever side it sits on) and
      # laterally shifted along that side (to separate two dataflows
      # sharing the same hop), each as a fraction of the box's relevant
      # dimension.
      DATAFLOW_THROUGH_MARGIN = 0.2
      DATAFLOW_LATERAL_MARGIN = 0.15

      # How far a point may sit from the straight chord between its
      # neighbors and still be dropped by
      # `Geometry.simplify_points` -- small relative to
      # typical box/gap sizes, enough to thin out a few-pixel routing jog
      # without erasing a real detour around an obstacle.
      DATAFLOW_SIMPLIFY_TOLERANCE = 6.0

      # The sharpest direction change a dataflow's line is allowed to make
      # at any single point, in degrees (0 = dead straight, 180 = a full
      # reversal) -- like a fiber optic cable's minimum bend radius, the
      # line simply isn't allowed to kink tighter than this anywhere.
      DATAFLOW_MAX_TURN_ANGLE = 55.0

      # How far a dataflow's true source/destination stub extends straight
      # out from the box, perpendicular to whichever side it exits/enters
      # on, before the rest of the route takes over.
      DATAFLOW_ENDPOINT_STUB = 20.0

      # How far apart the entry/exit points of a same-side "loop" dip sit
      # from each other, straddling the router's own boundary touch point --
      # small enough to still read as one hop's single junction, big enough
      # to give `Geometry.limit_turn_angles` two real points to shape a
      # smooth loop out of, rather than one point trying (and failing, see
      # `dataflow_backtracks?`'s doc comment) to represent a full reversal
      # by itself.
      DATAFLOW_LOOP_SEPARATION = 10.0

      # `obstacle_map` can be shared with `EdgeRouting` over the same boxes.
      def initialize(graph, boxes, obstacle_map: ObstacleMap.new(boxes))
        @graph = graph
        @boxes = boxes
        @obstacle_map = obstacle_map
      end

      def compute_routes(edge_sibling_paths)
        edge_siblings = Native::PackedPaths.new(edge_sibling_paths)
        other_dataflow_segments = []

        routed = expanded_dataflows.map do |df|
          hops = df.hops
          positioned_hops = hops.map { |hop| positioned(hop) }

          segments = route_segments(hops, positioned_hops, edge_siblings.followed_by(other_dataflow_segments))
          other_dataflow_segments.concat(segments)

          through_points = nudge_intermediate_hops!(df, hops, positioned_hops, segments)
          ensure_endpoint_stubs!(segments, positioned_hops)

          merged = merge_segments(segments)
          relaxed = relax_and_clamp(merged, through_points)

          DataflowRoute.new(dataflow: df, points: relaxed)
        end
        reconcile_dataflow_forks!(routed)
        routed
      end

      private

      def positioned(node)
        Layout::PositionedNode.new(node, @boxes[node.id])
      end

      # Routes every hop-to-hop segment with the same obstacle-avoiding
      # `EdgeRouter.route` a plain edge gets, simplified with Ramer-
      # Douglas-Peucker to thin the router's own jogs before any of the
      # dataflow-specific nudging/stubbing below runs.
      def route_segments(hops, positioned_hops, sibling_paths)
        positioned_hops.each_cons(2).with_index.map do |(from, to), i|
          points = EdgeRouter.route(from.box, to.box, nil, from_shape: from.shape, to_shape: to.shape,
                                                           obstacles: @obstacle_map.excluding(hops[i], hops[i + 1]),
                                                           sibling_paths: sibling_paths)
          Geometry.simplify_points(points, DATAFLOW_SIMPLIFY_TOLERANCE)
        end
      end

      # The route entering an intermediate hop and the route leaving it
      # don't necessarily land on the same side of its box (an L-shaped
      # path enters from the top and leaves to the right, say) -- nudging
      # each independently would give the hop two distinct points,
      # close together but at different angles, which read as an extra,
      # slightly unnatural micro-bend right where the flow touches the
      # box. So the ordinary case re-anchors the outgoing segment to the
      # same (single, nudged-in) point the incoming one arrives at, rather
      # than giving it its own independently-computed exit point -- the box
      # is touched at exactly one off-center interior point. The one case
      # that isn't an improvement is when entry and exit land on the *same*
      # side (`dataflow_backtracks?`): a single shared point there can only
      # read as a sharp reversal, never a pass-through, so that case gets
      # its own small two-point loop instead (`dataflow_loop_into_box`).
      # Mutates `segments` in place; returns the resulting through-point ->
      # box map, needed later to keep angle-relaxation from pulling a
      # through-point back outside its box.
      def nudge_intermediate_hops!(df, hops, positioned_hops, segments)
        through_points = {}

        (1..(hops.length - 2)).each do |i|
          sign = dataflow_hop_offset_signs.fetch([df.id, hops[i].id])
          box = positioned_hops[i].box
          entry_src = segments[i - 1].last
          side = box.side_of(entry_src)

          if side.nil?
            # The router's candidate happened not to land exactly on any
            # side of the box (rare, but possible for a bridge-routed
            # candidate) -- nothing to nudge or clamp.
            segments[i][0] = entry_src
          elsif dataflow_backtracks?(box, side, segments[i][1])
            # The route entering this hop and the route leaving it touch the
            # *same* side, with departure continuing on further past that
            # side still -- pushing one shared point into the interior would
            # force the line to double back across ground it just covered
            # (a single point can't read as a loop, only a reversal spike).
            # Two distinct points, close together but each pushed in only a
            # little, give the spline an actual small loop to draw instead.
            entry_point, exit_point = dataflow_loop_into_box(box, entry_src, side)
            segments[i - 1][-1] = entry_point
            segments[i][0] = exit_point
            through_points[entry_point] = box
            through_points[exit_point] = box
          else
            entry_point = dataflow_nudge_into_box(box, entry_src, side, sign)
            segments[i - 1][-1] = entry_point
            segments[i][0] = entry_point
            through_points[entry_point] = box
          end
        end

        through_points
      end

      # The router is free to pick a route whose very first move runs
      # *along* the source box's own edge before turning (e.g. a
      # single-turn candidate that happens to leave from the bottom but
      # corners almost immediately) -- fine for a plain edge, but for a
      # dataflow's line it reads as barely leaving the box at all before
      # bending. Forces a visible perpendicular stub at the true source
      # and true destination (never touched by `nudge_intermediate_hops!`),
      # then re-simplifies: the stub above is inserted blind to whatever
      # corner the router may have already placed close to the same box
      # (routing around a sibling near the destination, say), and
      # re-simplifying cleans up the near-duplicate cluster that creates,
      # the same way the earlier per-segment simplify thinned the router's
      # own jogs. RDP still keeps the stub whenever it's a real,
      # differently-angled deviation (the "hugs the box's own edge" case
      # this stub exists to fix) -- it only collapses genuinely redundant
      # points. Mutates `segments` in place.
      def ensure_endpoint_stubs!(segments, positioned_hops)
        segments[0] = dataflow_ensure_stub(segments[0], positioned_hops.first.box, at: :start)
        segments[-1] = dataflow_ensure_stub(segments[-1], positioned_hops.last.box, at: :end)

        segments[0] = Geometry.simplify_points(segments[0], DATAFLOW_SIMPLIFY_TOLERANCE)
        segments[-1] = Geometry.simplify_points(segments[-1], DATAFLOW_SIMPLIFY_TOLERANCE)
      end

      # Consecutive segments share their exact junction point by
      # construction (the last point of one is also the first point of the
      # next), so concatenating them, dropping each segment's duplicate
      # leading point, yields one seamless polyline from true source to
      # true destination.
      def merge_segments(segments)
        merged = []
        segments.each { |segment| segment.each { |point| merged << point unless merged.last == point } }
        merged
      end

      # `limit_turn_angles` relaxes a point toward the midpoint of its
      # *neighbors*, with no idea some points carry the extra meaning of
      # "this is what makes the line visibly cross through this box" -- a
      # sharp enough turn there can relax the point right back out of the
      # box, quietly undoing that. Clamps exactly the through-points back
      # inside their box after relaxing; everything else is smoothed
      # normally.
      def relax_and_clamp(merged, through_points)
        through_indices = through_points.filter_map { |point, box| (idx = merged.index(point)) && [idx, box] }

        relaxed = Geometry.limit_turn_angles(merged, DATAFLOW_MAX_TURN_ANGLE)
        through_indices.each { |idx, box| relaxed[idx] = clamp_point_to_box(relaxed[idx], box) }
        relaxed
      end

      # For every dataflow's every *intermediate* hop (not its first/last --
      # those are the flow's true source/destination and stay on the box
      # boundary), a deterministic +-1 assigned by the order dataflows using
      # that node as an intermediate hop were declared -- so two dataflows
      # sharing a hop (e.g. two servers both reporting through the same
      # `mgmt_lan`) offset to opposite sides of it instead of drawing
      # exactly on top of each other.
      def dataflow_hop_offset_signs
        return @dataflow_hop_offset_signs if defined?(@dataflow_hop_offset_signs)

        # A hop used by only one dataflow has nothing to separate from --
        # the lateral shift's only job is keeping two dataflows through the
        # same hop apart, and applying it anyway just adds an arbitrary,
        # unmotivated kink (the line swings aside for no reason, then has
        # to swing back). Only hops shared by 2+ dataflows get a real,
        # alternating sign; every other hop gets 0 (through dead-center
        # laterally, still offset perpendicular into the box).
        totals = Hash.new(0)
        expanded_dataflows.each { |df| df.hops[1..-2].to_a.each { |hop| totals[hop.id] += 1 } }

        counts = Hash.new(0)
        @dataflow_hop_offset_signs = {}

        expanded_dataflows.each do |df|
          df.hops[1..-2].to_a.each do |hop|
            if totals[hop.id] < 2
              @dataflow_hop_offset_signs[[df.id, hop.id]] = 0
            else
              index = counts[hop.id]
              counts[hop.id] += 1
              @dataflow_hop_offset_signs[[df.id, hop.id]] = index.even? ? -1 : 1
            end
          end
        end

        @dataflow_hop_offset_signs
      end

      # Pushes a point that sits on `box`'s boundary (as computed by the
      # normal obstacle-avoiding router) `DATAFLOW_THROUGH_MARGIN` into its
      # interior, plus a lateral shift along that same side so two
      # dataflows sharing this hop separate instead of exactly overlapping
      # -- deliberately *not* re-routing anything: the segments on either
      # side of this point were already routed by the same
      # obstacle-avoiding, sibling-aware `EdgeRouter.route` a plain edge
      # gets, so their overall shape (which corridor they take through the
      # diagram) is untouched. Moving only this one shared point is what
      # makes the line visibly continue into the box instead of stopping
      # at its edge, without risking a route that cuts a raw diagonal
      # across unrelated content. Only called for the ordinary case where
      # the route leaving this hop continues on past a *different* side --
      # see `dataflow_loop_into_box` for the same-side case.
      def dataflow_nudge_into_box(box, point, side, sign)
        x, y = point
        case side
        when :top    then [x + (sign * box.width * DATAFLOW_LATERAL_MARGIN), y + (box.height * DATAFLOW_THROUGH_MARGIN)]
        when :bottom then [x + (sign * box.width * DATAFLOW_LATERAL_MARGIN), y - (box.height * DATAFLOW_THROUGH_MARGIN)]
        when :left   then [x + (box.width * DATAFLOW_THROUGH_MARGIN), y + (sign * box.height * DATAFLOW_LATERAL_MARGIN)]
        when :right  then [x - (box.width * DATAFLOW_THROUGH_MARGIN), y + (sign * box.height * DATAFLOW_LATERAL_MARGIN)]
        end
      end

      # Whether the outgoing segment's next stop (`point`) already lies back
      # outside `box` on the very `side` the incoming route just touched,
      # i.e. the route touches this hop and immediately turns back the way
      # it came rather than passing on to a new side.
      def dataflow_backtracks?(box, side, point)
        case side
        when :top    then point[1] < box.top
        when :bottom then point[1] > box.bottom
        when :left   then point[0] < box.left
        when :right  then point[0] > box.right
        end
      end

      # The same-side counterpart to `dataflow_nudge_into_box`: the route
      # entering and the route leaving this hop touch the same side and
      # neither continues on to a new one, so there's no single interior
      # point that reads as "passes through" -- only a small loop can. Two
      # distinct points, offset from each other along the touched side and
      # both pushed only a little into the interior (capped well under
      # `DATAFLOW_THROUGH_MARGIN`'s usual reach -- this dip has nowhere to
      # go but back out the way it came, so it stays modest), give the
      # spline an actual loop shape to draw instead of a single point
      # `limit_turn_angles` can only either leave as a sharp reversal or
      # (once `relax_and_clamp` clamps it back to the boundary) collapse
      # away entirely.
      def dataflow_loop_into_box(box, point, side)
        x, y = point
        push = [box.width, box.height, DATAFLOW_LOOP_SEPARATION * 1.6].min * 0.5
        half = DATAFLOW_LOOP_SEPARATION / 2.0
        case side
        when :top    then [[x - half, y + push], [x + half, y + push]]
        when :bottom then [[x - half, y - push], [x + half, y - push]]
        when :left   then [[x + push, y - half], [x + push, y + half]]
        when :right  then [[x - push, y - half], [x - push, y + half]]
        end
      end

      # Pulls `point` back to the nearest point still inside `box`, if it's
      # outside -- used to guarantee a through-point still reads as
      # "inside the box" after `limit_turn_angles` relaxes it, however far
      # that relaxation moved it.
      def clamp_point_to_box(point, box)
        [point[0].clamp(box.left, box.right), point[1].clamp(box.top, box.bottom)]
      end

      # Inserts (or extends) a visible straight stub at `segment`'s start
      # or end so a dataflow's line always leaves/enters its true source
      # and destination perpendicular to the box, the same idea as
      # `EdgeRouter::BridgePath::BRIDGE_STUB` does for a bridge candidate --
      # capped at 60% of the distance to the next real point, so a stub can
      # never overshoot past a box that happens to sit close by.
      def dataflow_ensure_stub(segment, box, at:)
        anchor = at == :start ? segment.first : segment.last
        far_end = at == :start ? segment.last : segment.first
        side = box.side_of(anchor)
        return segment unless side

        # Capped against the segment's overall far end, not just its very
        # next point -- a route whose first move is already a sharp bend
        # close to the box (a short corner within the same segment) would
        # otherwise choke the stub down to almost nothing right where it
        # matters most.
        stub_length = [DATAFLOW_ENDPOINT_STUB, Geometry.point_distance(anchor, far_end) * 0.6].min
        return segment if stub_length < 1.0

        x, y = anchor
        stub = case side
               when :top    then [x, y - stub_length]
               when :bottom then [x, y + stub_length]
               when :left   then [x - stub_length, y]
               when :right  then [x + stub_length, y]
               end

        at == :start ? [anchor, stub, *segment[1..]] : [*segment[0..-2], stub, anchor]
      end

      # One dataflow's full route: every hop-to-hop segment is routed with
      # the exact same obstacle-avoiding `EdgeRouter.route` a real edge
      # gets, terminating at each hop's real box boundary same as always --
      # then every *intermediate* hop's shared junction point (the last
      # point of one segment, which is also the first point of the next)
      # is nudged into that box's interior (`dataflow_nudge_into_box`), so
      # the line visibly continues into the component instead of just
      # touching its edge. Consecutive segments share their exact junction
      # point by construction, so concatenating them (dropping each
      # segment's duplicate leading point) yields one seamless polyline
      # from true source to true destination.
      # Flattens every `Graph::DataFlow` into the same shape
      # `compute_routes`/`dataflow_hop_offset_signs` already expect (an
      # object responding to `#id`/`#hops`/`#label`/`#color`) -- a grouped
      # dataflow's shared prefix/suffix becomes its own synthetic,
      # unlabeled entry (drawn once, not once per branch), and each branch
      # becomes its own entry connecting the prefix's last node through its
      # own hops to the suffix's first node. `Legend::Inventory` reads
      # `@graph.dataflows` directly instead of this -- one legend row per
      # *authored* dataflow, not per branch/trunk piece.
      def expanded_dataflows
        return @expanded_dataflows if defined?(@expanded_dataflows)

        @expanded_dataflows = @graph.dataflows.flat_map do |df|
          next [df] unless df.group

          g = df.group
          has_prefix_trunk = g.prefix.length >= 2
          has_suffix_trunk = g.suffix.length >= 2
          has_trunk = has_prefix_trunk || has_suffix_trunk
          label_policy = BranchLabelPolicy.new(g, has_trunk: has_trunk)
          shared_label = label_policy.shared_label

          entries = []
          if has_prefix_trunk
            attrs = { "color" => df.color }
            attrs["label"] = shared_label if shared_label
            entries << Graph::DataFlow.new(id: "#{df.id}$prefix", hops: g.prefix, attrs: attrs, group: nil,
                                           line: df.line, origin: df)
          end
          if has_suffix_trunk
            attrs = { "color" => df.color }
            attrs["label"] = shared_label if shared_label && !has_prefix_trunk
            entries << Graph::DataFlow.new(id: "#{df.id}$suffix", hops: g.suffix, attrs: attrs, group: nil,
                                           line: df.line, origin: df)
          end

          g.branches.each_with_index do |b, i|
            chain = [g.prefix.last, *b.hops, g.suffix.first].compact
            entries << Graph::DataFlow.new(id: "#{df.id}$branch#{i}", hops: chain, attrs: label_policy.attrs_for(b, i), group: nil,
                                           line: df.line, origin: df)
          end
          entries
        end
      end

      # Every entry sharing a `hop group` is routed independently
      # (`compute_routes` has no idea two entries touch the same box until
      # after both are routed), so `EdgeRouter` is free to pick a
      # different side/point of that shared box for the trunk's arrival
      # than for each branch's departure -- drawn as-is, that reads as two
      # separate, slightly offset lines rather than one line that splits.
      # Snapping every branch's fork-adjacent endpoint to the trunk's own
      # endpoint (already sitting on/near that same box) closes that gap --
      # the same "reconcile the shared junction after independent routing"
      # idea `dataflow_nudge_into_box` already applies within one flow's own
      # hops, just applied here across sibling branches instead.
      def reconcile_dataflow_forks!(routed)
        by_id = routed.to_h { |r| [r.dataflow.id, r] }

        @graph.dataflows.each do |df|
          next unless df.group

          prefix_entry = by_id["#{df.id}$prefix"]
          suffix_entry = by_id["#{df.id}$suffix"]
          branch_entries = (0...df.group.branches.length).map { |i| by_id.fetch("#{df.id}$branch#{i}") }

          if prefix_entry
            fork_point = prefix_entry.points.last
            branch_entries.each { |r| r.points[0] = fork_point }
          end

          next unless suffix_entry

          merge_point = suffix_entry.points.first
          branch_entries.each { |r| r.points[-1] = merge_point }
        end
      end
    end
  end
end
