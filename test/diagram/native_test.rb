# frozen_string_literal: true

require_relative "../test_helper"

# Differential tests: the native kernels must reproduce the pure-Ruby
# reference exactly -- the same crossing counts and the same chosen route
# for every edge, not merely close scores. Coordinates are snapped to a
# coarse grid so that collinear overlaps, box-edge touches and exact
# length ties (where a last-ulp difference would flip the choice) come up
# constantly rather than by chance.
class DiagramNativeTest < Minitest::Test
  def setup
    skip "native kernels not built (rake compile)" unless Archsight::Diagram::Native.available?
  end

  # .crossing_counts

  def test_crossing_counts_matches_path_metrics_crossing_count_for_every_path
    200.times do
      paths = Array.new(rng.rand(1..8)) { random_path }
      obstacles = Array.new(rng.rand(0..12)) { random_box }

      assert_equal paths.map { |path| Archsight::Diagram::EdgeRouter::PathMetrics.crossing_count(path, obstacles) },
                   Archsight::Diagram::Native.crossing_counts(paths, obstacles)
    end
  end

  # .score_paths

  def test_score_paths_gives_exactly_path_metrics_crossings_and_geometry_path_lengths
    200.times do
      paths = Array.new(rng.rand(1..8)) { random_path } + [[[grid(400), grid(400)]]]
      obstacles = Array.new(rng.rand(0..12)) { random_box }
      crossings, lengths, turns = Archsight::Diagram::Native.score_paths(paths, obstacles)

      assert_equal paths.map { |path| Archsight::Diagram::EdgeRouter::PathMetrics.crossing_count(path, obstacles) }, crossings
      assert_equal paths.map { |path| Archsight::Diagram::Geometry.turn_count(path) }, turns
      # `eql?`, not a tolerance: a last-ulp difference could flip a tie, and
      # a lone point's length stays Ruby's Integer 0.
      paths.zip(lengths) { |path, length| assert_operator Archsight::Diagram::Geometry.path_length(path), :eql?, length }
    end
  end

  def test_score_paths_counts_turns_exactly_as_geometry_turn_count_around_its_threshold
    paths = [
      [[0.0, 0.0]], [[0.0, 0.0], [10.0, 0.0]], [[0.0, 0.0], [10.0, 0.0], [20.0, 0.0]], # no segment / one / collinear
      [[0.0, 0.0], [10.0, 10.0], [20.0, 20.0]], # collinear, slanted
      [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0]], # one corner
      [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 10.0]], # two
      [[0.0, 0.0], [1.0, 0.0], [2.0, 5.0e-7]], # cross product 5e-7: below 1e-6, straight
      [[0.0, 0.0], [1.0, 0.0], [2.0, 2.0e-6]], # 2e-6: a turn
      [[0.0, 0.0], [10.0, 0.0], [0.0, 0.0]] # doubling back on itself is collinear
    ]
    _crossings, _lengths, turns = Archsight::Diagram::Native.score_paths(paths, [])

    assert_equal paths.map { |path| Archsight::Diagram::Geometry.turn_count(path) }, turns
    assert_equal [0, 0, 0, 0, 1, 2, 0, 1, 0], turns
  end

  # .interior_hits

  def test_interior_hits_matches_path_metrics_enters_interior_for_either_box
    metrics = Archsight::Diagram::EdgeRouter::PathMetrics
    200.times do
      a = random_box
      b = random_box
      # Runs exactly along `a`'s edges and just inside them, where the
      # EDGE_EPSILON shrink decides the answer.
      along = [[a.left, a.top], [a.right, a.top], [a.right, a.bottom]]
      inside = [[a.left + 0.5, a.top - 20.0], [a.left + 0.5, a.bottom + 20.0]]
      paths = Array.new(rng.rand(1..8)) { random_path } + [along, inside]

      assert_equal paths.map { |path| metrics.enters_interior?(path, a) || metrics.enters_interior?(path, b) },
                   Archsight::Diagram::Native.interior_hits(paths, a, b)
    end
  end

  def test_interior_hits_declines_a_non_float_coordinate
    assert_nil Archsight::Diagram::Native.interior_hits([[[0, 0], [10, 0]]], random_box, random_box)
  end

  # .refine_line_overlap!

  def test_refine_line_overlap_picks_the_same_route_for_every_edge_as_the_ruby_sweep
    40.times do
      native = ruby_routed_edges(rng.rand(1..30))
      reference = native.map(&:dup)

      in_ruby { routing.refine_line_overlap!(reference) }

      assert_same true, Archsight::Diagram::Native.refine_line_overlap!(native, Archsight::Diagram::EdgeRouting::LINE_OVERLAP_REFINEMENT_ROUNDS)

      assert_equal reference.map(&:points), native.map(&:points)
      assert_equal chosen_indices(reference), chosen_indices(native)
    end
  end

  def test_refine_line_overlap_breaks_a_tie_exactly_like_ruby_s_compensated_sum
    edge = Archsight::Diagram::EdgeRouting::RoutedEdge.new(points: tie_tied, scored: tie_scored)
    siblings = tie_siblings.map do |path|
      Archsight::Diagram::EdgeRouting::RoutedEdge.new(points: path, scored: [{ path: path, crossing: 0, length: 0.0 }])
    end

    assert_same true, Archsight::Diagram::Native.refine_line_overlap!([edge, *siblings], 2)
    assert_same tie_tied, edge.points
  end

  def test_refine_line_overlap_declines_changing_nothing_when_a_coordinate_isn_t_a_float
    edge_paths = ruby_routed_edges(3)
    edge_paths.first.scored.first[:path][0] = [0, 0]
    before = edge_paths.map(&:points)

    assert_nil Archsight::Diagram::Native.refine_line_overlap!(edge_paths, 2)
    assert_equal before, edge_paths.map(&:points)
  end

  def test_refine_line_overlap_declines_when_a_current_route_isn_t_one_of_its_own_scored_candidates
    edge_paths = ruby_routed_edges(3)
    edge_paths.last.points = edge_paths.last.points.map(&:dup)

    assert_nil Archsight::Diagram::Native.refine_line_overlap!(edge_paths, 2)
  end

  # .select_best

  def test_select_best_picks_the_same_candidate_as_edge_router_select_best
    300.times do
      scored = random_scored
      siblings = random_siblings
      # A sibling identical to one of the candidates, now and then.
      siblings << scored.sample(random: rng)[:path].map(&:dup) if rng.rand(3).zero?

      index = Archsight::Diagram::Native.select_best(scored, siblings)

      assert_same ruby_select_best(scored, siblings), scored[index][:path]
    end
  end

  def test_select_best_breaks_a_tie_exactly_like_ruby_s_compensated_sum
    assert_equal 0, Archsight::Diagram::Native.select_best(tie_scored, tie_siblings)
    assert_same tie_tied, ruby_select_best(tie_scored, tie_siblings)
  end

  def test_select_best_is_what_edge_router_select_best_uses_when_there_are_siblings
    assert_same tie_tied, Archsight::Diagram::EdgeRouter.select_best(tie_scored, sibling_paths: tie_siblings)
  end

  def test_select_best_declines_when_there_are_no_siblings_a_sibling_coordinate_isn_t_a_float_or_a_sibling_path_is_empty
    scored = random_scored

    assert_nil Archsight::Diagram::Native.select_best(scored, [])
    assert_nil Archsight::Diagram::Native.select_best(scored, [[[0, 0], [10.0, 0.0]]])
    assert_nil Archsight::Diagram::Native.select_best(scored, [[[0.0, 0.0], [10.0, 0.0]], []])
  end

  # ObstacleMap's shared box table

  def test_obstacle_map_keeps_excluding_s_boxes_and_order_frozen
    boxes, obstacles, skip_ids = obstacle_map_case

    assert_equal boxes.except(*skip_ids).values, obstacles
    assert_predicate obstacles, :frozen?
    refute_nil obstacles.native_table
  end

  def test_obstacle_map_counts_crossings_exactly_as_path_metrics_over_the_excluded_list
    100.times do
      _boxes, obstacles, _skip = obstacle_map_case
      paths = Array.new(rng.rand(1..6)) { Array.new(rng.rand(2..5)) { [rng.rand(0..80) * 5.0, rng.rand(0..80) * 5.0] } }
      expected = paths.map { |path| Archsight::Diagram::EdgeRouter::PathMetrics.crossing_count(path, obstacles.to_a) }

      assert_equal expected, Archsight::Diagram::Native.crossing_counts(paths, obstacles)
      assert_equal expected, Archsight::Diagram::Native.crossing_counts(paths, obstacles.to_a)
    end
  end

  def test_rendering_with_on_demand_bridge_lanes_is_byte_identical_to_the_ruby_reference
    # Three edges into boxes of one row: two of them only separate onto
    # outer lanes via `EdgeRouting#separate_bridge_lanes!`, which re-runs
    # the (native) refine sweep with those extra candidates.
    source = <<~SRC
      layer {
        component "a" { }
        component "b" { }
        component "c" { }
        component "d" { }
      }
      a -> c
      a -> d
      b -> d
    SRC

    assert_equal in_ruby { Archsight::Diagram.render(source) }, Archsight::Diagram.render(source)
  end

  # .bridge_scan

  def test_bridge_scan_gives_bridge_path_bridge_candidates_the_same_candidates_as_its_ruby_scans
    300.times do
      a = coarse_box
      b = coarse_box
      obstacles = Array.new(rng.rand(0..20)) { coarse_box }
      # Now and then a box flush against one of `a`'s sides: a zero gap.
      obstacles << Archsight::Diagram::Layout::Box.new(a.left - 10.0, a.y, 20.0, a.height).tap(&:freeze_bounds!) if rng.rand(3).zero?

      assert_equal in_ruby { Archsight::Diagram::EdgeRouter::BridgePath.bridge_candidates(a, b, obstacles) },
                   Archsight::Diagram::EdgeRouter::BridgePath.bridge_candidates(a, b, obstacles)
    end
  end

  def test_bridge_scan_reports_no_facing_obstacle_as_an_infinite_gap
    a = Archsight::Diagram::Layout::Box.new(0.0, 0.0, 10.0, 10.0).tap(&:freeze_bounds!)

    Archsight::Diagram::Native.bridge_scan(a, a, []).first(4).each do |gap|
      assert_equal Float::INFINITY, gap
    end
  end

  # .rect_overlap_counts

  def test_rect_overlap_counts_counts_only_strict_intersections_like_label_placer_rects_intersect
    node = Archsight::Diagram::Layout::Box.new(15.0, 15.0, 10.0, 10.0).tap(&:freeze_bounds!) # 10..20 on both axes
    queries = [rect(20.0, 10.0, 30.0, 20.0), rect(19.0, 10.0, 30.0, 20.0), rect(0.0, 0.0, 10.0, 10.0)]
    placed = Archsight::Diagram::Native.pack_rects([rect(25.0, 10.0, 35.0, 20.0)])

    assert_equal [1, 2, 0], Archsight::Diagram::Native.rect_overlap_counts(queries, Archsight::Diagram::Native.pack_boxes([node]), placed)
  end

  def test_rect_overlap_counts_places_every_label_where_label_placer_s_ruby_scoring_would
    30.times do
      boxes = Array.new(rng.rand(1..25)) { |i| [:"n#{i}", coarse_box] }.to_h
      routes = Array.new(rng.rand(1..30)) do
        [Array.new(rng.rand(2..4)) { [rng.rand(0..80) * 5.0, rng.rand(0..80) * 5.0] }, "label #{"x" * rng.rand(0..12)}"]
      end
      place_all = ->(placer) { routes.map { |points, label| placer.place_label_along(points, label) } }

      assert_equal in_ruby { place_all.call(Archsight::Diagram::Renderer::LabelPlacer.new(boxes)) },
                   place_all.call(Archsight::Diagram::Renderer::LabelPlacer.new(boxes))
    end
  end

  # .path_rect_hits

  def test_path_rect_hits_counts_the_same_crossing_lines_as_label_placer_s_ruby_fallback
    rect_class = Archsight::Diagram::Renderer::LabelPlacer::Rect
    100.times do
      paths = Array.new(rng.rand(1..12)) { random_path }
      rects = Array.new(rng.rand(1..14)) do
        left = grid(400)
        top = grid(400)
        rect_class.new(left, left + grid(120), top, top + grid(40))
      end
      own = rng.rand(-1...paths.length)
      placer = Archsight::Diagram::Renderer::LabelPlacer.new({})
      in_ruby { placer.register_paths(paths) }

      assert_equal rects.map { |r| placer.send(:path_hit_count, r, own) },
                   Archsight::Diagram::Native.path_rect_hits(Archsight::Diagram::Native.pack_paths(paths), rects, own)
    end
  end

  def test_places_every_label_where_the_ruby_scoring_would_with_lines_and_containers_registered
    30.times do
      boxes = Array.new(rng.rand(1..15)) { |i| [:"n#{i}", coarse_box] }.to_h
      containers = Array.new(rng.rand(0..4)) { |i| [:"g#{i}", coarse_box] }.to_h
      routes = Array.new(rng.rand(1..20)) do
        [Array.new(rng.rand(2..4)) { [rng.rand(0..80) * 5.0, rng.rand(0..80) * 5.0] }, "label #{"x" * rng.rand(0..12)}"]
      end
      place_all = lambda do
        placer = Archsight::Diagram::Renderer::LabelPlacer.new(boxes, containers: containers)
        placer.register_paths(routes.map(&:first))
        routes.map { |points, label| placer.place_label_along(points, label) }
      end

      assert_equal in_ruby { place_all.call }, place_all.call
    end
  end

  # PackedPaths

  def test_packed_paths_scores_a_packed_prefix_plus_its_tail_the_same_as_the_plain_list
    100.times do
      prefix = Array.new(rng.rand(0..15)) { random_path }
      rest = Array.new(rng.rand(1..6)) { random_path }
      packed = Archsight::Diagram::Native::PackedPaths.new(prefix)
      siblings = packed.followed_by(rest)
      # Like `DataflowRouting#nudge_intermediate_hops!`, mutate a tail
      # path in place after the list was built.
      rest.sample(random: rng)[-1] = [grid(400), grid(400)]
      scored = random_scored

      assert_equal prefix + rest, siblings
      assert_same ruby_select_best(scored, prefix + rest), scored[Archsight::Diagram::Native.select_best(scored, siblings)][:path]
    end
  end

  def test_packed_paths_declines_to_pack_a_prefix_with_an_empty_or_non_float_path
    refute_predicate Archsight::Diagram::Native::PackedPaths.new([[]]), :packed?
    refute_predicate Archsight::Diagram::Native::PackedPaths.new([[[0, 0], [1.0, 1.0]]]), :packed?
  end

  # Kernels

  def test_kernels_rejects_malformed_offsets_instead_of_reading_out_of_bounds
    points = [0.0, 0.0, 10.0, 0.0].pack("d*")

    error = assert_raises(ArgumentError) { Archsight::Diagram::Native::Kernels.crossing_counts(points, [0, 5].pack("l*"), "", "") }
    assert_match(/last offset/, error.message)
    error = assert_raises(ArgumentError) { Archsight::Diagram::Native::Kernels.crossing_counts(points, [0, 2, 1].pack("l*"), "", "") }
    assert_match(/not monotonic/, error.message)
  end

  def test_kernels_rejects_malformed_sibling_offsets_in_select_best
    points = [0.0, 0.0, 10.0, 0.0].pack("d*")
    args = [points, [0, 2].pack("l*"), [0].pack("l*"), [10.0].pack("d*")]

    error = assert_raises(ArgumentError) do
      Archsight::Diagram::Native::Kernels.select_best(*args, points, [0, 3].pack("l*"), Archsight::Diagram::Native.refine_params)
    end
    assert_match(/last offset/, error.message)
    error = assert_raises(ArgumentError) do
      Archsight::Diagram::Native::Kernels.select_best(*args, points, [0, 0, 2].pack("l*"), Archsight::Diagram::Native.refine_params)
    end
    assert_match(/has no points/, error.message)
  end

  private

  def rng = @rng ||= Random.new(1234)

  # Steps of 0.1 -- not exactly representable -- so sums actually round,
  # and a summation order other than Ruby's shows up as a flipped tie.
  def grid(max) = rng.rand(0..(max / 10)) * 0.1

  def random_path
    points = [[grid(400), grid(400)]]
    rng.rand(1..4).times do
      x, y = points.last
      # Mostly axis-aligned hops (like OrthogonalPath's), sometimes diagonal.
      points << case rng.rand(3)
                when 0 then [grid(400), y]
                when 1 then [x, grid(400)]
                else [grid(400), grid(400)]
                end
    end
    points
  end

  def random_box
    Archsight::Diagram::Layout::Box.new(grid(400), grid(400), grid(120) + 10.0, grid(80) + 10.0)
  end

  def random_scored
    candidates = Array.new(rng.rand(1..6)) { random_path }
    # A duplicate candidate now and then, like a straight route that
    # coincides with an orthogonal one.
    candidates << candidates.first.map(&:dup) if rng.rand(4).zero?
    obstacles = Array.new(rng.rand(0..6)) { random_box }
    candidates.map do |path|
      { path: path, crossing: Archsight::Diagram::EdgeRouter::PathMetrics.crossing_count(path, obstacles),
        length: Archsight::Diagram::Geometry.path_length(path) }
    end
  end

  def ruby_routed_edges(edge_count)
    Array.new(edge_count) do
      scored = random_scored
      points = Archsight::Diagram::EdgeRouter.select_best(scored, sibling_paths: [])
      Archsight::Diagram::EdgeRouting::RoutedEdge.new(points: points, scored: scored)
    end
  end

  # Runs the block with the kernels switched off -- the pure-Ruby reference.
  def in_ruby(&)
    stub_singleton(Archsight::Diagram::Native, :available?, false, &)
  end

  # Replaces the singleton method `obj.name` with one returning `value`
  # for the duration of the block.
  def stub_singleton(obj, name, value)
    orig = obj.method(name)
    obj.define_singleton_method(name) { |*| value }
    yield
  ensure
    obj.define_singleton_method(name, orig)
  end

  def ruby_select_best(scored, sibling_paths)
    in_ruby { Archsight::Diagram::EdgeRouter.select_best(scored, sibling_paths: sibling_paths) }
  end

  # A box on a 10-unit grid with sizes in steps of 10, so edges land on
  # multiples of 5: boxes that exactly touch, zero gaps and shared edges
  # (where a strict vs non-strict comparison decides) come up constantly.
  def coarse_box
    b = Archsight::Diagram::Layout::Box.new(rng.rand(0..40) * 10.0, rng.rand(0..40) * 10.0,
                                            rng.rand(1..8) * 10.0, rng.rand(1..6) * 10.0)
    b.freeze_bounds!
    b
  end

  # A node-like object for `ObstacleMap#excluding`.
  def ancestor_chain = @ancestor_chain ||= Struct.new(:ancestor_ids)

  # Two equally long candidates whose overlap scores tie *only* under
  # Ruby's compensated `sum`: the first (`tie_tied`) overlaps one sibling
  # stretch of 1.4000000000000001; the second (`tie_rival`) overlaps three
  # stretches (0.1, 0.30000000000000004, 1.0) that Ruby's `sum` adds up to
  # that same value, but a naive `+=` loop to 1.4 -- which would let the
  # second win the tie the first should keep. Their `length`s are zeroed
  # so adding them can't round that one-ulp difference away.
  def tie_end_x = @tie_end_x ||= 14 * 0.1
  def tie_tied = @tie_tied ||= [[0.0, 5.0], [tie_end_x, 5.0]]
  def tie_rival = @tie_rival ||= [[0.0, 0.0], [tie_end_x, 0.0]]
  def tie_scored = @tie_scored ||= [tie_tied, tie_rival].map { |path| { path: path, crossing: 0, length: 0.0 } }
  def tie_siblings = @tie_siblings ||= [[[0.0, 0.0], [0.1, 0.0], [4 * 0.1, 0.0], [tie_end_x, 0.0]], [[0.0, 5.0], [tie_end_x, 5.0]]]

  def chosen_indices(edge_paths)
    edge_paths.map { |ep| ep.scored.index { |s| s[:path].equal?(ep.points) } }
  end

  # .refine_line_overlap!
  def routing = @routing ||= Archsight::Diagram::EdgeRouting.new(nil, {})

  # .select_best
  def random_siblings
    Array.new(rng.rand(1..25)) do
      case rng.rand(8)
      when 0 then [[grid(400), grid(400)]] # a lone point: no segments at all
      else random_path
      end
    end
  end

  # ObstacleMap's shared box table
  def obstacle_map_case
    boxes = Array.new(rng.rand(1..30)) { |i| [:"b#{i}", coarse_box] }.to_h
    skip_ids = boxes.keys.sample(rng.rand(0..4), random: rng)
    from = ancestor_chain.new(skip_ids.take(2))
    to = ancestor_chain.new(skip_ids.drop(2) + [:not_a_box])
    [boxes, Archsight::Diagram::ObstacleMap.new(boxes).excluding(from, to), skip_ids]
  end

  # .rect_overlap_counts
  def rect(left, top, right, bottom) = { left: left, top: top, right: right, bottom: bottom }
end
