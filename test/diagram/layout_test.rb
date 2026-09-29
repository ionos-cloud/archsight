# frozen_string_literal: true

require_relative "../test_helper"

class DiagramLayoutTest < Minitest::Test
  def test_keeps_sibling_leaf_nodes_from_overlapping
    source = <<~SRC
      component "a" { label "A" }
      component "b" { label "B" }
      component "c" { label "C" }
      a -> b
      b -> c
      c -> a
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    boxes = %w[a b c].map { |id| result.boxes[id] }

    boxes.combination(2).each { |x, y| assert_same false, overlap?(x, y) }
  end

  def test_orients_a_chain_of_connected_nodes_to_read_top_to_bottom
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "d" { }
      a -> b
      b -> c
      c -> d
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    %w[a b c d].each_cons(2) do |from_id, to_id|
      assert_operator result.boxes[to_id].y, :>, result.boxes[from_id].y
    end
  end

  def test_aligns_two_connected_top_level_roots_on_the_same_x_center_instead_of_leaving_them_offset
    # Regression test: repulsion/attraction pull along whatever diagonal
    # two nodes happen to be on, and the top-down flow bias only
    # constrains vertical separation — without a dedicated horizontal
    # alignment force, a much wider root (e.g. a big container) and a
    # narrower one connected by a single edge (e.g. an application above
    # the stack it calls into) settle at an arbitrary x offset instead of
    # reading as directly above/below each other.
    source = <<~SRC
      component "app" { label "Application" }
      group "wide" {
        label "A Wide Container"
        component "x" { label "Something With A Long Label In It" }
        component "y" { label "Y" }
        x -> y
      }
      app -> x
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    assert_in_delta result.boxes["wide"].x, result.boxes["app"].x, 1.0
  end

  def test_exactly_aligns_a_chain_of_3_connected_top_level_roots_not_just_an_approximate_pairwise_pull
    # Regression test: apply_align is a weak per-pair spring during the
    # force simulation, so with 3+ roots chained together it converges
    # only approximately — each pair can't perfectly satisfy the whole
    # chain at once, leaving a visible residual offset even though each
    # pair is individually close. A deterministic pass after the
    # simulation should make the whole chain share one exact x-center.
    source = <<~SRC
      boundary "top" {
        component "a" { label "A" }
      }
      stack "middle" {
        component "b" { label "A Very Long Label To Force This Rank Wide" }
        component "c" { label "C" }
      }
      boundary "bottom" {
        component "d" { label "D" }
      }
      a -> b
      c -> d
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    top, middle, bottom = %w[top middle bottom].map { |id| result.boxes[id] }

    assert_equal middle.x, top.x
    assert_equal bottom.x, middle.x
  end

  def test_keeps_siblings_with_no_edges_between_them_from_drifting_apart_without_bound
    # Regression test: a group of children with no mutual edges (e.g.
    # alternative drivers that don't talk to each other) has nothing but
    # mutual repulsion acting on it; without a centering force, it drifts
    # apart over the simulation instead of settling at a bounded distance.
    source = <<~SRC
      group "filesystems" {
        component "ext4"  { label "ext4" }
        component "xfs"   { label "XFS" }
        component "btrfs" { label "Btrfs" }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    group_box = result.boxes["filesystems"]

    assert_operator group_box.width, :<, 1000
    assert_operator group_box.height, :<, 1000
  end

  def test_keeps_every_child_box_fully_inside_its_parent_group_s_box
    source = <<~SRC
      group "vpc" {
        component "a" { label "A" }
        component "b" { label "B" }
        a -> b
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    vpc_box = result.boxes["vpc"]
    %w[a b].each do |id|
      child_box = result.boxes[id]

      assert_operator child_box.left, :>=, vpc_box.left
      assert_operator child_box.right, :<=, vpc_box.right
      assert_operator child_box.top, :>=, vpc_box.top
      assert_operator child_box.bottom, :<=, vpc_box.bottom
    end
  end

  def test_keeps_nested_groups_from_overlapping_their_sibling_group
    source = <<~SRC
      group "vpc" {
        group "public" {
          component "lb" { label "Load Balancer" }
        }
        group "private" {
          component "api" { label "API" }
          component "db" { label "DB" }
          api -> db
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    assert_same false, overlap?(result.boxes["public"], result.boxes["private"])
  end

  def test_orients_a_child_toward_an_external_connection_instead_of_leaving_it_in_another_edge_s_path
    # Regression test: "api" connects out to "lb" (outside the "private"
    # group); "db" only connects to "api". Without taking that external
    # connection into account, the "private" group could arbitrarily place
    # "db" between "lb" and "api", putting the straight lb -> api edge
    # directly through the "db" box.
    source = <<~SRC
      group "vpc" {
        group "public" {
          component "lb" { label "Load Balancer" }
        }
        group "private" {
          component "api" { label "API Service" }
          component "db" { label "Postgres" }
          api -> db
        }
      }
      lb -> api
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    lb = result.boxes["lb"]
    api = result.boxes["api"]
    db = result.boxes["db"]

    # api should end up on the side of "private" nearer lb, not db.
    assert_operator (api.x - lb.x).abs, :<, (db.x - lb.x).abs

    # The straight lb -> api edge must not cut through the unrelated db box.
    edge_point = Archsight::Diagram::EdgeRouter::StraightPath.straight_path(lb, api)
    crosses_db = edge_point.each_cons(2).any? do |(x1, y1), (x2, y2)|
      segment_intersects_box?(x1, y1, x2, y2, db)
    end

    assert_same false, crosses_db
  end

  def test_places_layer_children_on_a_shared_centerline_left_to_right_in_declaration_order
    source = <<~SRC
      layer "l" {
        component "a" { label "A" }
        component "b" { label "Wider Label B" }
        component "c" { label "C" }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)
    a, b, c = %w[a b c].map { |id| result.boxes[id] }

    assert_equal b.y, a.y
    assert_equal c.y, b.y
    assert_operator a.right, :<=, b.left
    assert_operator b.right, :<=, c.left
  end

  def test_stacks_children_top_to_bottom_in_declaration_order_stretched_to_the_widest_child
    source = <<~SRC
      stack "s" {
        component "a" { label "A" }
        component "b" { label "A Much Wider Label" }
        component "c" { label "C" }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)
    a, b, c = %w[a b c].map { |id| result.boxes[id] }

    assert_operator a.bottom, :<=, b.top
    assert_operator b.bottom, :<=, c.top
    assert_equal b.width, a.width
    assert_equal c.width, b.width
    assert_equal b.width, a.width # stretched to the widest child, not just equal by coincidence
    assert_equal b.x, a.x
    assert_equal c.x, b.x
  end

  def test_never_reorders_a_stack_s_children_even_when_an_external_connection_would_otherwise_flip_them
    source = <<~SRC
      component "trigger" { }
      stack "s" {
        component "a" { }
        component "b" { }
      }
      trigger -> b
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    assert_operator result.boxes["a"].y, :<, result.boxes["b"].y
  end

  def test_aligns_a_dataflow_s_connected_top_level_roots_on_one_x_center_same_as_a_real_edge_chain_would
    # Mirrors "exactly aligns a chain of 3+ connected top-level roots"
    # above, but the chain is a `dataflow`'s hops instead of plain edges
    # -- proving consecutive hops feed the same attraction/alignment
    # forces a real edge does (see `Layout#attraction_edges`).
    source = <<~SRC
      boundary "top" {
        component "a" { label "A" }
      }
      stack "middle" {
        component "b" { label "A Very Long Label To Force This Rank Wide" }
        component "c" { label "C" }
      }
      boundary "bottom" {
        component "d" { label "D" }
      }
      dataflow "flow" {
        hop "a"
        hop "b"
        hop "d"
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    top, middle, bottom = %w[top middle bottom].map { |id| result.boxes[id] }

    assert_equal middle.x, top.x
    assert_equal bottom.x, middle.x
  end

  def test_inverts_the_flow_bias_for_an_implements_edge
    # Regression test: `up -> mid` (a plain dependency) correctly pulls
    # "up" above "mid". Without inverting the flow bias, `down -> mid`
    # (an *implements* edge, source in "down") would pull "down" above
    # "mid" too, the same as a dependency would -- fighting the desired
    # top-to-bottom reading (up, then mid, then down) with the interface
    # sandwiched in the middle instead of on top.
    source = <<~SRC
      group "g" {
        layer "up" { component "u" { } }
        layer "mid" { component "m" { } }
        layer "down" { component "d" { } }
      }
      u -> m
      d -> m { relation "implements" }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    up, mid, down = %w[up mid down].map { |id| result.boxes[id] }

    assert_operator up.y, :<, mid.y
    assert_operator mid.y, :<, down.y
  end

  def test_widens_the_gap_between_adjacent_stack_items_connected_by_an_edge_so_the_arrow_is_visible
    # Regression test: STACK_GAP (a tight touching gap, for the plain
    # "tower" look) is smaller than an arrowhead, so an edge drawn between
    # two adjacent stack items needs more room than that or the arrow
    # disappears into the gap.
    source = <<~SRC
      stack "s" {
        component "a" { }
        component "b" { }
        component "c" { }
      }
      a -> b
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    a, b, c = %w[a b c].map { |id| result.boxes[id] }

    assert_equal Archsight::Diagram::Theme::DEFAULT.sibling_gap, b.top - a.bottom
    assert_equal Archsight::Diagram::Theme::DEFAULT.stack_gap, c.top - b.bottom
  end

  def test_widens_a_stack_s_own_gap_via_a_gap_attr_absolute_plain_percentage_or_a_signed_relative_delta
    [
      ["40", 40.0],
      ["150%", Archsight::Diagram::Theme::DEFAULT.stack_gap * 1.5],
      ["+200%", Archsight::Diagram::Theme::DEFAULT.stack_gap * 3]
    ].each do |raw, expected_gap|
      source = <<~SRC
        stack "s" {
          gap "#{raw}"
          component "a" { }
          component "b" { }
        }
      SRC
      graph = build_graph(source)
      result = Archsight::Diagram::Layout.compute(graph)
      a, b = %w[a b].map { |id| result.boxes[id] }

      assert_in_delta expected_gap, b.top - a.bottom, 0.01
    end
  end

  def test_widens_a_layer_s_own_gap_via_a_gap_attr_the_same_way
    source = <<~SRC
      layer "l" {
        gap "+100%"
        component "a" { }
        component "b" { }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)
    a, b = %w[a b].map { |id| result.boxes[id] }

    assert_in_delta Archsight::Diagram::Theme::DEFAULT.sibling_gap * 2, b.left - a.right, 0.01
  end

  def test_widens_a_group_boundary_s_own_force_simulated_gap_via_a_gap_attr_too
    # An edge pulls "a"/"b" as close together as `apply_attraction`/
    # `apply_flow` want, so the minimum gap `resolve_overlaps` enforces
    # afterward is what's actually binding here -- widening it should
    # widen the final resting distance by exactly that much.
    %w[group boundary].each do |kind|
      source = <<~SRC
        #{kind} "c" {
          gap "+300%"
          component "a" { }
          component "b" { }
        }
        a -> b
      SRC
      graph = build_graph(source)
      result = Archsight::Diagram::Layout.compute(graph)
      a, b = %w[a b].map { |id| result.boxes[id] }
      top, bottom = [a, b].sort_by(&:top)

      assert_in_delta Archsight::Diagram::Theme::DEFAULT.sibling_gap * 4, bottom.top - top.bottom, 0.01
    end
  end

  def test_keeps_the_tight_default_gap_between_stack_ranks_even_when_their_descendants_have_an_edge
    # Regression test: a stack's ranks are often composite containers
    # (e.g. two `layer`s), and an edge between two things buried inside
    # different ranks used to widen the rank-to-rank gap the same way a
    # *direct* edge between the ranks themselves would — even blowing it
    # out further to fit an edge label's text. But that inner edge routes
    # to wherever its actual endpoints ended up, not necessarily through
    # the narrow strip between the ranks, so the gap should stay
    # consistent and tight regardless of what's nested inside each rank.
    source = <<~SRC
      stack "s" {
        layer "top" {
          component "a" { label "A" }
        }
        layer "bottom" {
          component "b" { label "B" }
        }
      }
      a -> b { label "a rather long label that would otherwise force the gap wide open" }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    top, bottom = %w[top bottom].map { |id| result.boxes[id] }

    assert_equal Archsight::Diagram::Theme::DEFAULT.stack_gap, bottom.top - top.bottom
  end

  def test_gives_an_anonymous_layer_stack_zero_padding_so_it_acts_as_a_pure_layout_hint
    # Regression test: an unnamed layer/stack renders no box, so it
    # shouldn't reserve PADDING/TITLE_HEIGHT space either -- its size
    # should be exactly its children's tight bounding box, otherwise it'd
    # leave a blank margin where a border would have been.
    source = <<~SRC
      boundary "b" {
        stack {
          component "a" { label "A" }
          layer {
            component "x" { label "X" }
            component "y" { label "Y" }
          }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    boundary_box = graph.roots.first
    anon_stack = boundary_box.children.first
    anon_layer = anon_stack.children.find(&:layer?)

    stack_box = result.boxes[anon_stack.id]
    layer_box = result.boxes[anon_layer.id]
    a = result.boxes["a"]
    x = result.boxes["x"]
    y = result.boxes["y"]

    # No padding: the anonymous stack's box hugs its children exactly.
    assert_equal a.top, stack_box.top
    assert_equal layer_box.bottom, stack_box.bottom
    assert_equal x.left, layer_box.left
    assert_equal y.right, layer_box.right
  end

  def test_allows_a_stack_to_contain_a_layer_packing_the_layer_s_peers_within_it_and_stretching_to_fit
    source = <<~SRC
      stack "s" {
        component "top" { label "Top" }
        layer "middle" {
          component "a" { label "A" }
          component "b" { label "B" }
          component "c" { label "C" }
        }
        component "bottom" { label "Bottom" }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    top, middle, bottom = %w[top middle bottom].map { |id| result.boxes[id] }
    a, b, c = %w[a b c].map { |id| result.boxes[id] }

    # Ranks stay in declaration order, stacked and touching (no gap other
    # than STACK_GAP), and every rank is stretched to the same width.
    assert_in_delta middle.top - Archsight::Diagram::Theme::DEFAULT.stack_gap, top.bottom, 0.01
    assert_in_delta bottom.top - Archsight::Diagram::Theme::DEFAULT.stack_gap, middle.bottom, 0.01
    assert_equal 1, [top.width, middle.width, bottom.width].uniq.length

    # Within the layer, its own peers are still packed left to right.
    assert_equal b.y, a.y
    assert_equal c.y, b.y
    assert_operator a.right, :<=, b.left
    assert_operator b.right, :<=, c.left

    # The layer's peers still fit entirely inside the stretched layer box.
    [a, b, c].each do |box|
      assert_operator box.left, :>=, middle.left
      assert_operator box.right, :<=, middle.right
    end
  end

  def test_centers_a_layer_s_peers_within_a_stack_s_width_stretch_instead_of_leaving_them_flush
    # Regression test: a narrow layer stacked alongside a much wider
    # sibling gets stretched to match it. Its own children were already
    # positioned (flush left, via padding) before that stretch happened,
    # so without re-centering they'd end up flush against one side of the
    # now-wider box instead of centered in it.
    source = <<~SRC
      stack "s" {
        component "wide" { label "A Very Long Label That Forces This Rank To Be Wide" }
        layer "narrow" {
          component "a" { label "A" }
          component "b" { label "B" }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    narrow = result.boxes["narrow"]
    a, b = %w[a b].map { |id| result.boxes[id] }

    content_left = a.left
    content_right = b.right
    left_margin = content_left - narrow.left
    right_margin = narrow.right - content_right

    assert_in_delta right_margin, left_margin, 0.5
  end

  def test_cascades_a_stack_s_width_stretch_into_a_single_child_boundary_s_own_child
    # Regression test: a boundary wrapping exactly one layer (e.g. a DMZ
    # containing one tier of APIs) got its own box stretched to match its
    # stack siblings, but the layer inside it only got recentered at its
    # old, narrower width — leaving a visible gap inside the boundary
    # instead of the inner layer spanning it edge to edge, the way a
    # layer that's a *direct* stack child already does.
    source = <<~SRC
      stack "s" {
        component "wide" { label "A Very Long Label To Force This Rank Extremely Wide" }
        boundary "b" {
          layer "inner" {
            component "x" { label "X" }
            component "y" { label "Y" }
          }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    wide = result.boxes["wide"]
    b = result.boxes["b"]
    inner = result.boxes["inner"]

    assert_equal wide.width, b.width
    assert_in_delta b.left + Archsight::Diagram::Theme::DEFAULT.padding, inner.left, 0.01
    assert_in_delta b.right - Archsight::Diagram::Theme::DEFAULT.padding, inner.right, 0.01
  end

  def test_never_stretches_a_circle_actor_leaf_s_box_even_as_the_sole_child_of_a_stretched_container
    # Regression test: a leaf's rendered shape can be tied to its box
    # size in ways a plain rectangle isn't (e.g. an actor's arm span
    # scales with box width, in Renderer#actor_icon_markup). Stretching
    # such a leaf to match an unrelated, much wider sibling would
    # visually distort it, so it should stay at its natural size while
    # still ending up centered in the space around it.
    source = <<~SRC
      stack "s" {
        component "wide" { label "A Very Long Label To Force This Rank Extremely Wide" }
        boundary "b" {
          actor "person" { label "P" }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    wide = result.boxes["wide"]
    b = result.boxes["b"]
    person = result.boxes["person"]

    assert_equal wide.width, b.width
    assert_operator person.width, :<, b.width
    assert_in_delta b.x, person.x, 0.01
  end

  def test_does_stretch_file_and_module_leaves_unlike_circle_actor
    # Regression test: these two shapes are plain-rectangle-ish (a
    # module is literally a sharp-cornered rectangle; a file's folded
    # corner is clamped to a fixed max size), so stretching either to
    # match a wider sibling doesn't distort it the way it would a
    # circle/actor -- STRETCHABLE_LEAF_SHAPES needs to list both.
    %w[file module].each do |shape|
      source = <<~SRC
        stack "s" {
          component "wide" { label "A Very Long Label To Force This Rank Extremely Wide" }
          component "narrow" { label "X"; shape "#{shape}" }
        }
      SRC
      graph = build_graph(source)
      result = Archsight::Diagram::Layout.compute(graph)

      assert_equal result.boxes["wide"].width, result.boxes["narrow"].width
    end
  end

  def test_opts_a_multi_child_container_into_stretching_each_child_not_just_recentering_via_an_extend_attr
    source = <<~SRC
      stack "s" {
        component "wide" { label "A Very Long Label To Force This Rank Extremely Wide" }
        layer {
          extend "true"
          component "a" { label "X" }
          component "b" { label "Y" }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    wide = result.boxes["wide"]
    a = result.boxes["a"]
    b = result.boxes["b"]

    # Both children grew (not just the row's own outer box + padding),
    # and the row's original gap between them is preserved exactly.
    assert_operator a.width, :>, 120.0
    assert_equal a.width, b.width # split evenly
    assert_in_delta Archsight::Diagram::Theme::DEFAULT.sibling_gap, b.left - a.right, 0.01

    # The re-flowed row spans exactly as wide as "wide", anchored so it
    # reads as one continuous row filling the available space, not just
    # centered-with-padding inside a wider box.
    assert_in_delta wide.left, a.left, 0.01
    assert_in_delta wide.right, b.right, 0.01
  end

  def test_leaves_a_multi_child_container_s_children_un_stretched_without_the_extend_attr_just_recentered
    source = <<~SRC
      stack "s" {
        component "wide" { label "A Very Long Label To Force This Rank Extremely Wide" }
        layer {
          component "a" { label "X" }
          component "b" { label "Y" }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    a = result.boxes["a"]
    b = result.boxes["b"]

    assert_equal Archsight::Diagram::Theme::DEFAULT.node_min_width, a.width # unstretched
    assert_equal Archsight::Diagram::Theme::DEFAULT.node_min_width, b.width
  end

  def test_inherits_extend_down_through_nested_containers_including_a_single_child_wrapper
    # Regression test: this used to stop propagating the moment an
    # intermediate single-child wrapper already happened to be exactly
    # wide enough on its own (its own width already matched the target,
    # bottom-up, purely by chance) -- since nothing further down needed
    # to *grow*, the cascade returned early before ever reaching the
    # deeply-nested stack that still needed to fan its own extend out to
    # its own children.
    source = <<~SRC
      stack "s" {
        extend "true"

        stack {
          component "wide" { label "A Very Long Label To Force This Rank Extremely Wide" }
        }

        stack {
          stack {
            component "narrow" { label "X"; shape "module" }
          }
          stack {
            component "other" { label "A Long Enough Label" }
          }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    wide = result.boxes["wide"]
    narrow = result.boxes["narrow"]

    assert_equal wide.width, narrow.width
  end

  def test_stops_extend_inheritance_at_an_explicit_extend_false_without_affecting_siblings
    source = <<~SRC
      stack "s" {
        extend "true"

        stack {
          component "wide" { label "A Very Long Label To Force This Rank Extremely Wide" }
        }

        layer {
          extend "false"
          component "a" { label "X" }
          component "b" { label "Y" }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    a = result.boxes["a"]
    b = result.boxes["b"]

    # Without the opt-out, both would have been split-stretched to fill
    # the rank's (wide-matching) width; "extend false" keeps them at
    # their own natural size instead, just recentered as a whole.
    assert_equal Archsight::Diagram::Theme::DEFAULT.node_min_width, a.width # unstretched
    assert_equal Archsight::Diagram::Theme::DEFAULT.node_min_width, b.width
  end

  def test_keeps_a_cross_axis_extended_rank_s_children_centered_on_the_new_width_not_the_stale_old_one
    # Regression test: growing each child's width without also moving it
    # to the new shared centerline (`Stacker#pack` positions every rank's
    # cross-axis coordinate at exactly half the shared width, regardless
    # of that rank's own width) left children off-center relative to
    # their own newly-widened box -- visibly spilling outside a sibling
    # group even though their width matched it exactly.
    source = <<~SRC
      stack "s" {
        extend "true"

        stack {
          component "wide" { label "A Very Long Label To Force This Rank Extremely Wide" }
        }

        stack {
          gap "0"
          component "a" { label "X"; shape "module" }
          component "b" { label "Y"; shape "module" }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    wide = result.boxes["wide"]
    a = result.boxes["a"]
    b = result.boxes["b"]

    assert_equal wide.width, a.width
    assert_in_delta wide.left, a.left, 0.01
    assert_in_delta wide.right, a.right, 0.01
    assert_in_delta wide.left, b.left, 0.01
    assert_in_delta wide.right, b.right, 0.01
  end

  def test_gives_top_level_roots_the_same_width_equalization_a_stack_gives_its_ranks
    # Regression test: this used to require wrapping unrelated top-level
    # roots in an explicit `stack` just to get them to share a width —
    # which rendered a visible, purely-cosmetic extra box. Root-level
    # width equalization should happen without one.
    source = <<~SRC
      boundary "small" {
        component "a" { label "A" }
      }
      stack "wide" {
        component "b" { label "A Very Long Label To Force This Rank Extremely Wide" }
        component "c" { label "C" }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    assert_equal result.boxes["wide"].width, result.boxes["small"].width
    assert_equal 2, graph.roots.length # no extra node introduced for the grouping
  end

  def test_lays_out_a_boundary_s_children_with_the_general_force_directed_simulation_like_a_group
    source = <<~SRC
      boundary "b" {
        component "a" { }
        component "b2" { }
        a -> b2
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    assert_same false, overlap?(result.boxes["a"], result.boxes["b2"])
  end

  def test_sizes_the_canvas_to_fit_the_whole_layout_with_a_margin
    graph = build_graph(%(component "a" { label "A" }\n))
    result = Archsight::Diagram::Layout.compute(graph)
    box = result.boxes["a"]

    assert_operator box.left, :>=, Archsight::Diagram::Theme::DEFAULT.canvas_margin - 0.01
    assert_operator box.top, :>=, Archsight::Diagram::Theme::DEFAULT.canvas_margin - 0.01
    assert_operator result.width, :>=, box.right
    assert_operator result.height, :>=, box.bottom
  end

  def test_keeps_a_single_line_label_s_box_size_exactly_as_before_multi_line_support
    graph = build_graph(%(component "a" { label "Just one line" }\n))
    box = Archsight::Diagram::Layout.compute(graph).boxes["a"]

    assert_equal Archsight::Diagram::Theme::DEFAULT.node_height, box.height
  end

  def test_grows_a_node_s_height_for_each_extra_line_in_a_multi_line_label_without_affecting_a_1_line_sibling
    source = <<~SRC
      component "multi" { label "Line one\\nLine two\\nLine three" }
      component "single" { label "One line" }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    assert_equal Archsight::Diagram::Theme::DEFAULT.node_height + (2 * Archsight::Diagram::Theme::DEFAULT.label_line_height),
                 result.boxes["multi"].height
    assert_equal Archsight::Diagram::Theme::DEFAULT.node_height, result.boxes["single"].height
  end

  def test_sizes_a_multi_line_label_s_width_off_its_longest_line_not_the_whole_string_s_length
    source = <<~SRC
      component "multi" { label "Short\\nA much longer second line here" }
    SRC
    graph = build_graph(source)
    box = Archsight::Diagram::Layout.compute(graph).boxes["multi"]

    longest_line = "A much longer second line here"

    assert_equal [(longest_line.length * Archsight::Diagram::Theme::DEFAULT.char_width) + Archsight::Diagram::Theme::DEFAULT.node_label_padding,
                  Archsight::Diagram::Theme::DEFAULT.node_min_width].max, box.width
  end

  def test_extend_height_grows_a_layer_child_s_box_to_its_tallest_sibling_keeping_content_top_aligned
    source = <<~SRC
      layer {
        stack "short" {
          label "Short"
          extend "height"
          component "a" { label "A" }
          component "b" { label "B" }
        }
        stack "tall" {
          label "Tall"
          component "c" { label "C" }
          component "d" { label "D" }
          component "e" { label "E" }
          component "f" { label "F" }
          component "g" { label "G" }
        }
        stack "plain" {
          label "Plain"
          component "h" { label "H" }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    short = result.boxes["short"]
    tall = result.boxes["tall"]
    plain = result.boxes["plain"]
    a = result.boxes["a"]
    b = result.boxes["b"]

    assert_in_delta tall.height, short.height, 0.01
    assert_in_delta tall.top, short.top, 0.01
    assert_in_delta tall.bottom, short.bottom, 0.01

    # Only the frame grew: its items keep their natural size, top-aligned.
    assert_equal Archsight::Diagram::Theme::DEFAULT.node_height, a.height
    assert_equal Archsight::Diagram::Theme::DEFAULT.node_height, b.height
    assert_in_delta short.top + Archsight::Diagram::Theme::DEFAULT.padding + Archsight::Diagram::Theme::DEFAULT.title_height, a.top, 0.01

    # A sibling without the attr keeps its natural height.
    assert_operator plain.height, :<, tall.height
  end

  def test_extend_height_leaves_inherited_width_extension_untouched
    source = <<~SRC
      stack "s" {
        extend "true"
        component "wide" { label "A Very Long Label To Force This Rank Extremely Wide" }
        layer {
          extend "height"
          component "a" { label "X" }
          component "b" { label "Y" }
        }
      }
    SRC
    graph = build_graph(source)
    result = Archsight::Diagram::Layout.compute(graph)

    wide = result.boxes["wide"]
    a = result.boxes["a"]
    b = result.boxes["b"]

    assert_in_delta wide.left, a.left, 0.01
    assert_in_delta wide.right, b.right, 0.01
  end

  def test_lays_out_a_columns_table_exactly_like_the_hand_written_layer_of_stacks
    table = <<~SRC
      stack "t" {
        label "T"
        columns "2"
        component "a" { label "A" }
        component "b" { label "B" }
        component "c" { label "A Much Longer Label" }
        component "d" { label "D" }
      }
    SRC
    nested = <<~SRC
      stack "t" {
        label "T"
        layer {
          stack {
            component "a" { label "A" }
            component "b" { label "B" }
          }
          stack {
            component "c" { label "A Much Longer Label" }
            component "d" { label "D" }
          }
        }
      }
    SRC
    from_table = Archsight::Diagram::Layout.compute(build_graph(table)).boxes
    from_nested = Archsight::Diagram::Layout.compute(build_graph(nested)).boxes

    %w[t a b c d].each do |id|
      assert_equal from_nested[id].to_a, from_table[id].to_a, id
    end
  end

  def test_never_mirrors_a_columns_table_to_line_a_column_up_with_an_outside_neighbor
    source = <<~SRC
      group "g" {
        columns "2"
        component "a" { }
        component "b" { }
        component "c" { }
        component "d" { }
      }
      component "far" { }
      far -> a
      far -> b
    SRC
    boxes = Archsight::Diagram::Layout.compute(build_graph(source)).boxes

    assert_operator boxes["a"].x, :<, boxes["c"].x
    assert_operator boxes["b"].x, :<, boxes["d"].x
  end

  def test_stacks_a_single_columns_table_in_a_layer_top_to_bottom
    source = %(layer "g" {\n columns "1"\n component "a" { }\n component "b" { }\n component "c" { }\n}\n)
    boxes = Archsight::Diagram::Layout.compute(build_graph(source)).boxes

    assert_in_delta boxes["a"].x, boxes["b"].x, 0.01
    assert_in_delta boxes["b"].x, boxes["c"].x, 0.01
    assert_operator boxes["a"].y, :<, boxes["b"].y
    assert_operator boxes["b"].y, :<, boxes["c"].y
  end

  def test_compact_theme_packs_a_stack_with_its_own_tighter_gaps_and_a_smaller_canvas
    source = <<~SRC
      group "g" {
        stack "s" {
          component "a" { label "Alpha" }
          component "b" { label "Beta" }
          component "c" { label "Gamma" }
          a -> b
        }
      }
    SRC
    graph = build_graph(source)
    compact_theme = Archsight::Diagram::Theme::COMPACT
    compact = Archsight::Diagram::Layout.compute(graph, theme: compact_theme)
    default = Archsight::Diagram::Layout.compute(graph)

    a, b, c = %w[a b c].map { |id| compact.boxes[id] }

    assert_equal compact_theme.sibling_gap, b.top - a.bottom # directly connected ranks
    assert_equal compact_theme.stack_gap, c.top - b.bottom
    assert_equal compact_theme.node_height, a.height
    assert_same compact_theme, compact.theme
    assert_operator compact.width, :<, default.width
    assert_operator compact.height, :<, default.height
  end

  def test_compact_theme_sizes_a_node_from_real_glyph_widths_ignoring_markdown_markers
    theme = Archsight::Diagram::Theme::COMPACT
    graph = build_graph(%(component "a" { label "**Cloud DNS**\\nManaged authoritative anycast DNS" }\n))
    box = Archsight::Diagram::Layout.compute(graph, theme: theme).boxes["a"]

    # The widest line, at the compact node font size (Helvetica: 176.1px).
    text_width = Archsight::Diagram::TextMetrics.rendered_width("Managed authoritative anycast DNS", font_size: theme.node_font_size)

    assert_in_delta 176.08, text_width, 0.01
    assert_in_delta text_width + theme.node_label_padding, box.width, 0.01
  end

  def test_cozy_theme_lands_between_default_and_compact
    source = <<~SRC
      group "g" {
        layer "l" {
          component "a" { label "**Alpha service**\\nDoes the first thing" }
          component "b" { label "Beta" }
        }
        component "c" { label "Gamma" }
        a -> c
      }
    SRC
    graph = build_graph(source)
    widths = %w[default cozy compact].map do |name|
      Archsight::Diagram::Layout.compute(graph, theme: Archsight::Diagram::Theme.fetch(name)).width
    end

    assert_equal widths.sort.reverse, widths
    assert_equal 3, widths.uniq.length
  end

  def test_a_labeled_edge_never_shrinks_a_stack_s_explicit_larger_gap
    source = <<~SRC
      stack "s" {
        gap "150"
        component "a" { }
        component "b" { }
        component "c" { }
        a -> b { label "checks" }
      }
    SRC
    result = Archsight::Diagram::Layout.compute(build_graph(source))
    a, b, c = %w[a b c].map { |id| result.boxes[id] }

    assert_in_delta 150.0, b.top - a.bottom, 0.01 # labeled pair
    assert_in_delta 150.0, c.top - b.bottom, 0.01
  end

  def test_a_labeled_edge_still_widens_a_stack_s_default_gap_for_its_label
    source = <<~SRC
      stack "s" {
        component "a" { }
        component "b" { }
        a -> b { label "checks" }
      }
    SRC
    result = Archsight::Diagram::Layout.compute(build_graph(source))

    assert_in_delta Archsight::Diagram::Theme::DEFAULT.rank_edge_label_gap,
                    result.boxes["b"].top - result.boxes["a"].bottom, 0.01
  end

  def test_a_labeled_edge_never_shrinks_a_layer_s_explicit_larger_gap
    source = <<~SRC
      layer "l" {
        gap "200"
        component "a" { }
        component "b" { }
        a -> b { label "x" }
      }
    SRC
    result = Archsight::Diagram::Layout.compute(build_graph(source))

    assert_in_delta 200.0, result.boxes["b"].left - result.boxes["a"].right, 0.01
  end

  private

  def build_graph(source)
    Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
  end

  def overlap?(a, b)
    a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
  end

  def segment_intersects_box?(x1, y1, x2, y2, box)
    # Simple sampled check: fine for this regression test's straight, short segment.
    steps = 50
    (0..steps).any? do |i|
      t = i / steps.to_f
      x = x1 + ((x2 - x1) * t)
      y = y1 + ((y2 - y1) * t)
      x > box.left && x < box.right && y > box.top && y < box.bottom
    end
  end
end
