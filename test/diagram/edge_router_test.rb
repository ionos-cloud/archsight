# frozen_string_literal: true

require_relative "../test_helper"

class DiagramEdgeRouterTest < Minitest::Test
  def test_routes_a_straight_vertical_line_through_the_smaller_box_s_center_when_boxes_share_a_flush_right_edge
    # A wide box directly above a narrow one, both right-aligned -- the
    # generic center-to-center ray would otherwise exit through the
    # middle of the wide box's bottom edge, well to the left of the
    # narrow box, drawing a visibly diagonal line despite the flush edge.
    wide = box(400, 100, 400, 60) # left 200, right 600
    narrow = box(540, 200, 120, 60) # left 480, right 600 -- shares the right edge

    points = Archsight::Diagram::EdgeRouter::StraightPath.straight_path(wide, narrow)

    assert_equal narrow.x, points[0][0]
    assert_equal narrow.x, points[1][0]
    assert_equal wide.bottom, points[0][1]
    assert_equal narrow.top, points[1][1]
  end

  def test_routes_a_straight_vertical_line_through_the_smaller_box_s_center_when_boxes_share_a_flush_left_edge
    wide = box(400, 100, 400, 60) # left 200, right 600
    narrow = box(260, 200, 120, 60) # left 200, right 320 -- shares the left edge

    points = Archsight::Diagram::EdgeRouter::StraightPath.straight_path(wide, narrow)

    assert_equal narrow.x, points[0][0]
    assert_equal narrow.x, points[1][0]
  end

  def test_keeps_the_edge_s_own_direction_a_first_b_second_even_when_a_sits_geometrically_right_below_b
    # Regression test: `vertical_shared_edge_path`/`horizontal_shared_edge_path`
    # used to order their two points by which box was physically
    # above/below or left/right, not by which one is `a` (the edge's
    # source) -- so an edge whose source happened to sit to the right of
    # (or below) its target rendered with the arrowhead on the wrong
    # end, pointing back into the source instead of at the target.
    a_is_right = box(400, 100, 120, 60)
    b_is_left = box(200, 100, 120, 60)
    points = Archsight::Diagram::EdgeRouter::StraightPath.straight_path(a_is_right, b_is_left)

    assert_equal a_is_right.left, points.first[0] # a's own point comes first...
    assert_equal b_is_left.right, points.last[0] # ...b's point comes second, regardless of geometry
  end

  def test_still_draws_a_straight_vertical_line_when_boxes_already_share_the_same_center_x
    top = box(400, 100, 400, 60)
    bottom = box(400, 200, 120, 60)

    points = Archsight::Diagram::EdgeRouter::StraightPath.straight_path(top, bottom)

    assert_equal 400.0, points[0][0]
    assert_equal 400.0, points[1][0]
  end

  def test_falls_back_to_the_center_to_center_ray_when_boxes_share_no_edge
    a = box(0, 0, 100, 60)
    b = box(300, 200, 100, 60)

    points = Archsight::Diagram::EdgeRouter::StraightPath.straight_path(a, b)

    refute_equal points[1][0], points[0][0]
  end

  def test_routes_a_diagonal_orthogonal_edge_with_a_single_right_angle_turn_when_it_s_geometrically_safe
    # Regression test: a two-turn mid-jog always works, but reads worse
    # than a single corner when one is available -- here `a` sits above
    # and to the left of `b`, offset enough on both axes that a single
    # turn (exit a's side, one corner, straight into b's top) can't cut
    # through either box.
    a = box(636, 51, 120, 60)
    b = box(712, 234, 190, 60)

    points = Archsight::Diagram::EdgeRouter.route(a, b, "orthogonal")

    assert_equal 3, points.length
    assert_equal [b.x, a.y], points[1] # the single corner
  end

  def test_falls_back_to_a_two_turn_mid_jog_when_no_single_corner_is_safe
    # One below the other, offset on x but still overlapping it: each
    # single turn's corner would double back through a box, so only a
    # mid-jog, bent in the vertical gap between them, clears both.
    a = box(0, 0, 100, 60)
    b = box(10, 200, 100, 60) # spans -40..60: no entry point on its top lies beyond a's right edge (50)

    points = Archsight::Diagram::EdgeRouter.route(a, b, "orthogonal")

    assert_equal 4, points.length
    assert_equal [0, 30.0], points.first # leaves `a`'s bottom, facing `b`
    assert_equal [10, 170.0], points.last # enters `b`'s top
  end

  def test_offers_no_mid_jog_along_an_axis_the_two_boxes_overlap_on
    side_by_side = [box(0, 0, 100, 60), box(300, 0, 100, 60)] # overlap on y
    stacked = [box(0, 0, 100, 60), box(0, 200, 100, 60)] # overlap on x
    orthogonal = Archsight::Diagram::EdgeRouter::OrthogonalPath

    [side_by_side, stacked].each do |a, b|
      dx = b.x - a.x
      dy = b.y - a.y

      orthogonal::MID_JOG_RATIOS.each do |ratio|
        assert_nil orthogonal.mid_jog_vertical(a, b, dx, dy, ratio) if dy.zero?
        assert_nil orthogonal.mid_jog_horizontal(a, b, dx, dy, ratio) if dx.zero?
      end
    end
  end

  def test_never_offers_a_candidate_that_cuts_back_through_either_box_it_connects
    metrics = Archsight::Diagram::EdgeRouter::PathMetrics
    [
      [box(0, 0, 100, 60), box(300, 0, 100, 60)],
      [box(0, 0, 100, 60), box(0, 200, 100, 60)],
      [box(0, 0, 100, 60), box(300, 20, 100, 60)]
    ].each do |a, b|
      candidates = Archsight::Diagram::EdgeRouter::OrthogonalPath.orthogonal_candidates(a, b)

      refute_empty candidates
      candidates.each do |path|
        refute metrics.enters_interior?(path, a), "#{path.inspect} runs through its own source box"
        refute metrics.enters_interior?(path, b), "#{path.inspect} runs through its own target box"
      end
    end
  end

  def test_enters_interior_ignores_a_path_that_only_touches_the_box_s_boundary
    b = box(100, 100, 100, 60) # left 50, right 150, top 70, bottom 130
    metrics = Archsight::Diagram::EdgeRouter::PathMetrics

    refute metrics.enters_interior?([[150, 100], [300, 100]], b) # leaves from its right side
    refute metrics.enters_interior?([[50, 70], [150, 70]], b) # runs along its top edge
    assert metrics.enters_interior?([[100, 70], [100, 100], [300, 100]], b) # dips inside before leaving
  end

  # .side_of

  def test_side_of_identifies_which_side_of_a_box_a_point_sits_on
    b = box(100, 100, 200, 100) # left 0, right 200, top 50, bottom 150

    assert_equal :left, Archsight::Diagram::EdgeRouter::Attachment.side_of(b, [0, 80])
    assert_equal :right, Archsight::Diagram::EdgeRouter::Attachment.side_of(b, [200, 80])
    assert_equal :top, Archsight::Diagram::EdgeRouter::Attachment.side_of(b, [150, 50])
    assert_equal :bottom, Archsight::Diagram::EdgeRouter::Attachment.side_of(b, [150, 150])
    assert_nil Archsight::Diagram::EdgeRouter::Attachment.side_of(b, [150, 80]) # interior, not on any edge
  end

  # .shift_attachment

  def test_shift_attachment_shifts_only_the_leading_run_of_points_sharing_the_start_s_coordinate_on_that_axis
    # A single-turn path: the exit point and its corner both sit at
    # y = 51 (a left/right-side exit), the entry point doesn't -- only
    # the first two points should move.
    points = [[696.0, 51.0], [712.0, 51.0], [712.0, 204.0]]

    shifted = Archsight::Diagram::EdgeRouter::Attachment.shift_attachment(points, :y, 10.0, at: :start)

    assert_equal [[696.0, 61.0], [712.0, 61.0], [712.0, 204.0]], shifted
  end

  def test_shift_attachment_shifts_only_the_trailing_run_of_points_sharing_the_end_s_coordinate_on_that_axis
    points = [[696.0, 51.0], [712.0, 51.0], [712.0, 204.0]]

    shifted = Archsight::Diagram::EdgeRouter::Attachment.shift_attachment(points, :x, 5.0, at: :end)

    assert_equal [[696.0, 51.0], [717.0, 51.0], [717.0, 204.0]], shifted
  end

  def test_shift_attachment_leaves_a_straight_2_point_path_s_far_endpoint_untouched
    points = [[0.0, 0.0], [100.0, 80.0]]

    shifted = Archsight::Diagram::EdgeRouter::Attachment.shift_attachment(points, :y, 5.0, at: :start)

    assert_equal [[0.0, 5.0], [100.0, 80.0]], shifted
  end

  def test_shift_attachment_moves_only_the_near_endpoint_even_when_both_points_coincidentally_share_the_shift_coordinate
    # Regression test: `vertical_shared_edge_path` (and a straight edge
    # that's exactly horizontal/vertical) deliberately give both
    # endpoints the same coordinate on one axis -- a naive "leading run
    # of matching points" heuristic would then swallow the far endpoint
    # too and drag it along, which is exactly what broke
    # `aurora_agent -> qmon`/`-> vcb` once `aurora_agent`'s exits were
    # spread across its side: an edge to a box with only one
    # attachment still moved, and another missed its target entirely.
    points = [[398.0, 778.0], [374.0, 778.0]]

    shifted = Archsight::Diagram::EdgeRouter::Attachment.shift_attachment(points, :y, -15.0, at: :start)

    assert_equal [[398.0, 763.0], [374.0, 778.0]], shifted
  end

  # .bridge_candidates (via .orthogonal_path)

  def test_bridge_candidates_routes_around_an_obstacle_that_sits_squarely_between_two_boxes_at_a_shared_axis_level
    # Mirrors vcb / pbsdnmgr / cpd: an obstacle horizontally between
    # the source and target, overlapping both their y-ranges, so no
    # straight line, single turn, or in-between mid-jog can avoid it
    # -- only a bridge that leaves the shared y-band before crossing
    # can.
    source = box(500, 800, 120, 60) # left 440, right 560
    obstacle = box(300, 800, 120, 60) # left 240, right 360 -- directly between, same row
    target = box(150, 800, 120, 60) # left 90, right 210

    points = Archsight::Diagram::EdgeRouter.route(source, target, "orthogonal", obstacles: [obstacle])

    assert_equal 0, Archsight::Diagram::EdgeRouter.crossing_count(points, [obstacle])
  end

  def test_bridge_candidates_offers_one_loop_level_per_side_lanes_are_only_added_on_demand
    candidates = Archsight::Diagram::EdgeRouter::BridgePath.bridge_candidates(box(500, 500, 120, 60), box(100, 500, 120, 60), [])

    assert_equal 8, candidates.length
    assert_same(true, candidates.all? { |path| Archsight::Diagram::EdgeRouter::BridgePath.bridge?(path) })
  end

  def test_lane_variants_step_a_bridge_s_loop_outward_and_shift_its_entry_away_from_the_approach
    a = box(500, 500, 120, 60)
    b = box(100, 500, 120, 60) # same row: bottom = 530 for both
    bridge = Archsight::Diagram::EdgeRouter::BridgePath
    geometry = Archsight::Diagram::Geometry
    chosen = bridge.bridge_candidates(a, b, [])[1] # left exit, looping below both boxes

    variants = bridge.lane_variants(chosen, b)
    lanes = variants.first(bridge::BRIDGE_LANES - 1)
    shifted = variants.drop(bridge::BRIDGE_LANES - 1)

    assert_equal((1...bridge::BRIDGE_LANES).map { |lane| chosen[2][1] + (lane * bridge::BRIDGE_LANE_SPACING) },
                 lanes.map { |path| path[2][1] }) # outward = further down
    assert_equal bridge::BRIDGE_LANES, shifted.length # the original and every lane, entry shifted
    ([chosen] + lanes).zip(shifted).each do |plain, moved|
      assert_equal plain.first(3), moved.first(3) # same exit, stub and loop line
      assert_in_delta geometry.path_length(plain) + bridge::BRIDGE_ENTRY_OFFSET, geometry.path_length(moved), 0.01
    end
  end

  def test_lane_variants_ignores_anything_that_isn_t_a_bridge
    assert_equal [], Archsight::Diagram::EdgeRouter::BridgePath.lane_variants([[0, 0], [10, 0], [10, 10], [20, 10]], box(20, 10, 40, 40))
  end

  def test_bridge_candidates_leaves_the_source_box_perpendicular_to_whichever_side_it_exits_from_not_running_along_it
    # Regression test: a bridge's first segment used to keep the exit
    # point's coordinate on the exit axis fixed (e.g. same x for a
    # left/right exit), so it ran straight along the box's own edge
    # before ever moving away from it -- reading as an extension of
    # the box's outline rather than a line leaving it.
    a = box(500, 500, 120, 60) # left 440, right 560, top 470, bottom 530
    b = box(100, 100, 120, 60)

    candidates = Archsight::Diagram::EdgeRouter::BridgePath.bridge_candidates(a, b, [])
    candidates.each do |path|
      exit_point, next_point = path.first(2)
      horizontal_exit = Archsight::Diagram::EdgeRouter::PathMetrics.close?(exit_point[0], a.left) || Archsight::Diagram::EdgeRouter::PathMetrics.close?(exit_point[0], a.right)
      vertical_exit = Archsight::Diagram::EdgeRouter::PathMetrics.close?(exit_point[1], a.top) || Archsight::Diagram::EdgeRouter::PathMetrics.close?(exit_point[1], a.bottom)

      if horizontal_exit
        refute_equal exit_point[0], next_point[0] # moves in x -- perpendicular to a left/right edge
        assert_equal exit_point[1], next_point[1]
      else
        assert_same true, vertical_exit
        refute_equal exit_point[1], next_point[1] # moves in y -- perpendicular to a top/bottom edge
        assert_equal exit_point[0], next_point[0]
      end
    end
  end

  # .overlap_length / .collinear_overlap

  def test_overlap_length_measures_the_length_two_collinear_overlapping_segments_share
    overlap = Archsight::Diagram::EdgeRouter::PathMetrics.collinear_overlap([100.0, 0.0], [100.0, 100.0], [100.0, 40.0], [100.0, 140.0])

    assert_equal 60.0, overlap # shared from y=40 to y=100
  end

  def test_overlap_length_reports_zero_overlap_for_segments_that_only_cross_at_a_point
    overlap = Archsight::Diagram::EdgeRouter::PathMetrics.collinear_overlap([0.0, 0.0], [100.0, 0.0], [50.0, -50.0], [50.0, 50.0])

    assert_equal 0.0, overlap
  end

  def test_overlap_length_sums_overlap_across_every_segment_of_every_sibling_path
    path = [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]]
    siblings = [[[0.0, 0.0], [100.0, 0.0]], [[100.0, 0.0], [100.0, 60.0]]]

    assert_equal 160.0, Archsight::Diagram::EdgeRouter::PathMetrics.overlap_length(path, siblings) # 100 + 60
  end

  # .best_path with sibling_paths

  def test_best_path_prefers_an_otherwise_equal_candidate_that_doesn_t_run_along_a_sibling_edge_s_line
    overlapping = [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]]
    clear = [[0.0, 0.0], [0.0, 100.0], [100.0, 100.0]]
    sibling = [[0.0, 0.0], [100.0, 0.0]] # collinear with `overlapping`'s first segment

    best = Archsight::Diagram::EdgeRouter.best_path([overlapping, clear], [], sibling_paths: [sibling])

    assert_equal clear, best
  end

  def test_best_path_prefers_an_otherwise_equal_candidate_that_doesn_t_cross_a_sibling_edge_s_line
    crossing = [[0.0, 40.0], [0.0, 50.0], [100.0, 50.0], [100.0, 40.0]] # crosses the sibling's vertical run at (50, 50)
    clear = [[0.0, 40.0], [0.0, 30.0], [100.0, 30.0], [100.0, 40.0]] # jogs above the sibling's (narrow) span instead
    sibling = [[50.0, 40.0], [50.0, 60.0]]

    best = Archsight::Diagram::EdgeRouter.best_path([crossing, clear], [], sibling_paths: [sibling])

    assert_equal clear, best
  end

  # .anchor_point

  def test_anchor_point_slides_a_file_shape_s_anchor_off_its_chamfered_corner_and_onto_the_fold_s_own_diagonal
    b = box(100, 100, 120, 60) # right 160, top 70; the fold's diagonal runs (146,70) to (160,84)

    # Aimed into the corner from two different sides -- both would
    # naturally clip to the raw rectangle corner region without the
    # correction (one via the top edge, one via the right edge).
    via_top = Archsight::Diagram::EdgeRouter::StraightPath.anchor_point(b, 210.0, 35.0, shape: "file")
    via_right = Archsight::Diagram::EdgeRouter::StraightPath.anchor_point(b, 230.0, 50.0, shape: "file")

    [via_top, via_right].each do |(x, y)|
      assert_in_delta 76.0, x - y, 0.0001 # right(160) - fold(14) - top(70)
      assert_operator x, :>=, 146.0
      assert_operator x, :<=, 160.0
      assert_operator y, :>=, 70.0
      assert_operator y, :<=, 84.0
    end
  end

  def test_anchor_point_leaves_a_plain_rectangle_s_anchor_untouched_by_the_chamfer_correction_for_the_same_ray
    b = box(100, 100, 120, 60)
    point = Archsight::Diagram::EdgeRouter::StraightPath.anchor_point(b, 210.0, 35.0, shape: "rectangle")

    assert_equal 70.0, point[1] # still exits through the raw top edge...
    assert_operator point[0], :>, 146.0 # ...at an x the file shape's chamfer would have cut away
  end

  def test_anchor_point_doesn_t_change_a_file_shape_s_anchor_when_it_s_nowhere_near_the_chamfered_corner
    b = box(100, 100, 120, 60)
    straight_up_file = Archsight::Diagram::EdgeRouter::StraightPath.anchor_point(b, 100.0, -200.0, shape: "file")
    straight_up_rect = Archsight::Diagram::EdgeRouter::StraightPath.anchor_point(b, 100.0, -200.0, shape: "rectangle")

    assert_equal straight_up_rect, straight_up_file

    straight_left_file = Archsight::Diagram::EdgeRouter::StraightPath.anchor_point(b, -200.0, 100.0, shape: "file")
    straight_left_rect = Archsight::Diagram::EdgeRouter::StraightPath.anchor_point(b, -200.0, 100.0, shape: "rectangle")

    assert_equal straight_left_rect, straight_left_file
  end

  # .segments_cross?

  def test_segments_cross_is_true_when_two_segments_properly_cross
    assert_same true, Archsight::Diagram::EdgeRouter::PathMetrics.segments_cross?([0.0, 0.0], [100.0, 100.0], [0.0, 100.0], [100.0, 0.0])
  end

  def test_segments_cross_is_false_for_segments_that_only_touch_at_a_shared_endpoint
    assert_same false, Archsight::Diagram::EdgeRouter::PathMetrics.segments_cross?([0.0, 0.0], [100.0, 0.0], [100.0, 0.0], [100.0, 100.0])
  end

  def test_segments_cross_is_false_for_parallel_or_collinear_segments
    assert_same false, Archsight::Diagram::EdgeRouter::PathMetrics.segments_cross?([0.0, 0.0], [100.0, 0.0], [0.0, 50.0], [100.0, 50.0])
    assert_same false, Archsight::Diagram::EdgeRouter::PathMetrics.segments_cross?([0.0, 0.0], [100.0, 0.0], [20.0, 0.0], [80.0, 0.0])
  end

  def test_offers_a_straight_vertical_drop_at_each_box_s_center_that_lies_inside_both_spans
    wide = box(400, 300, 800, 40) # left 0, right 800
    above = box(150, 100, 100, 40) # left 100, right 200 -- entirely inside wide's span

    paths = Archsight::Diagram::EdgeRouter::StraightPath.aligned_paths(above, wide)

    assert_equal [[[150, above.bottom], [150, wide.top]]], paths # wide's center (400) is outside above's span
  end

  def test_aligned_paths_keep_the_edge_direction_when_the_source_is_the_lower_box
    wide = box(400, 300, 800, 40)
    above = box(150, 100, 100, 40)

    path = Archsight::Diagram::EdgeRouter::StraightPath.aligned_paths(wide, above).first

    assert_equal [150, wide.top], path.first
    assert_equal [150, above.bottom], path.last
  end

  def test_aligned_paths_run_horizontally_for_boxes_side_by_side_that_overlap_on_y
    tall = box(100, 300, 40, 600) # top 0, bottom 600
    beside = box(400, 150, 40, 100) # top 100, bottom 200

    path = Archsight::Diagram::EdgeRouter::StraightPath.aligned_paths(beside, tall).first

    assert_equal [[beside.left, 150], [tall.right, 150]], path
  end

  def test_aligned_paths_are_empty_when_the_boxes_do_not_overlap_on_either_axis_or_overlap_on_both
    a = box(0, 0, 100, 60)

    assert_empty Archsight::Diagram::EdgeRouter::StraightPath.aligned_paths(a, box(300, 200, 100, 60))
    assert_empty Archsight::Diagram::EdgeRouter::StraightPath.aligned_paths(a, box(50, 30, 100, 60))
  end

  def test_aligned_paths_stay_clear_of_the_shared_span_s_corners
    a = box(0, 0, 100, 60) # right edge at 50
    b = box(100, 200, 100, 60) # left edge at 50 -- the spans only touch

    assert_empty Archsight::Diagram::EdgeRouter::StraightPath.aligned_paths(a, b)

    c = box(95, 200, 100, 60) # left 45, right 145: the shared span is 45..50, narrower than the corner margins

    assert_empty Archsight::Diagram::EdgeRouter::StraightPath.aligned_paths(a, c)
  end

  def test_aligned_paths_only_anchor_an_elliptical_endpoint_at_its_own_center
    circle = box(150, 100, 60, 60) # left 120, right 180
    rect = box(160, 300, 200, 40) # its center (160) lies inside the circle's span, but is not the circle's own

    paths = Archsight::Diagram::EdgeRouter::StraightPath.aligned_paths(circle, rect, from_shape: "circle")

    assert_equal [[[150, circle.bottom], [150, rect.top]]], paths
  end

  def test_routes_a_box_straight_down_onto_a_wide_box_instead_of_angling_towards_its_center
    wide = box(400, 300, 800, 40)
    above = box(700, 100, 100, 40)

    points = Archsight::Diagram::EdgeRouter.route(above, wide, nil)

    assert_equal [[700, above.bottom], [700, wide.top]], points
  end

  def test_an_explicit_orthogonal_style_keeps_its_bends_even_when_a_straight_drop_is_possible
    wide = box(400, 300, 800, 40)
    above = box(700, 100, 100, 40)

    refute_equal 2, Archsight::Diagram::EdgeRouter.route(above, wide, "orthogonal").length
  end

  def test_prefers_a_longer_route_with_fewer_bends_among_routes_that_clear_the_same_boxes
    zig_zag = [[0.0, 0.0], [0.0, 50.0], [100.0, 50.0], [100.0, 100.0]] # 200 long, two turns
    one_corner = [[0.0, 0.0], [130.0, 0.0], [130.0, 100.0]] # 230 long, one turn
    much_longer = [[0.0, 0.0], [300.0, 0.0], [300.0, 100.0]] # 400 long: too big a detour to be worth a bend

    assert_equal one_corner, Archsight::Diagram::EdgeRouter.best_path([zig_zag, one_corner], [])
    assert_equal zig_zag, Archsight::Diagram::EdgeRouter.best_path([zig_zag, much_longer], [])
  end

  def test_extra_bends_never_outweigh_avoiding_a_box
    obstacle = box(50, 0, 20, 20)
    through = [[0.0, 0.0], [100.0, 0.0]] # straight, but draws through the obstacle
    around = [[0.0, 0.0], [0.0, 60.0], [100.0, 60.0], [100.0, 0.0]] # 3 more bends' worth of turns, clear

    assert_equal around, Archsight::Diagram::EdgeRouter.best_path([through, around], [obstacle])
  end

  def test_offers_a_single_turn_entering_the_target_off_center_when_the_centered_entry_is_blocked
    source = box(0, 0, 100, 60)
    target = box(300, 300, 400, 60) # top edge spans x 100..500
    blocker = box(300, 150, 40, 40) # sits on the drop into the target's center

    points = Archsight::Diagram::EdgeRouter.route(source, target, "orthogonal", obstacles: [blocker])

    assert_equal 3, points.length # exit, one corner, entry -- not a two-turn jog
    refute_equal target.x, points.last[0]
    assert_equal 0, Archsight::Diagram::EdgeRouter.crossing_count(points, [blocker])
  end

  def test_obstacle_map_leaves_out_ignored_boxes_such_as_undrawn_wrappers
    boxes = { "a" => box(0, 0, 10, 10), "wrapper" => box(50, 50, 100, 100), "b" => box(200, 200, 10, 10), "c" => box(300, 0, 10, 10) }
    node = Struct.new(:ancestor_ids)
    from = node.new(["a"])
    to = node.new(["b"])

    assert_equal [boxes["wrapper"], boxes["c"]], Archsight::Diagram::ObstacleMap.new(boxes).excluding(from, to).to_a
    assert_equal [boxes["c"]], Archsight::Diagram::ObstacleMap.new(boxes, ignoring: ["wrapper"]).excluding(from, to).to_a
  end

  def test_an_undrawn_anonymous_wrapper_does_not_push_a_line_off_the_port_next_to_it
    # Regression test: `cli` has a slanted line to `target`, and the anonymous
    # stack wrapping `other` sits in the way of the only free port -- it draws
    # nothing, so it must not count as something to avoid.
    source = <<~SRC
      layer {
        component "cli" { }
        stack {
          component "other" { }
        }
      }
      component "target" { }
      cli -> target
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    layout = Archsight::Diagram::Layout.compute(graph)
    renderer = Archsight::Diagram::Renderer.new(graph, layout)
    obstacle_map = renderer.instance_variable_get(:@edge_routing).instance_variable_get(:@obstacle_map)
    anonymous = graph.nodes_by_id.values.select { |n| n.anonymous? && !n.leaf? }

    refute_empty anonymous
    obstacles = obstacle_map.excluding(graph.nodes_by_id["cli"], graph.nodes_by_id["target"]).to_a

    anonymous.each { |n| refute(obstacles.any? { |b| b.equal?(layout.boxes[n.id]) }, "#{n.id} is an obstacle") }
  end

  private

  def box(x, y, width, height)
    Archsight::Diagram::Layout::Box.new(x, y, width, height)
  end
end
