# frozen_string_literal: true

require_relative "../test_helper"

class DiagramRankedLayoutTest < Minitest::Test
  EXAMPLES = File.expand_path("fixtures", __dir__)

  def test_ranks_a_flat_dag_top_to_bottom_by_default_every_edge_pointing_down
    graph, layout = layout(File.read(File.join(EXAMPLES, "dag.asd")))

    graph.edges.each do |e|
      assert_operator layout.boxes[e.from.id].bottom, :<, layout.boxes[e.to.id].top, "#{e.from.id} -> #{e.to.id}"
    end
    assert_empty overlapping(layout, graph.nodes_by_id.keys)
  end

  def test_leaves_a_dag_under_three_ranks_deep_to_the_force_layout_under_auto
    source = %(component "a" { }\ncomponent "b" { }\ncomponent "c" { }\na -> b\na -> c\n)

    assert_equal positions(layout(source, "off")), positions(layout(source))
  end

  def test_ranks_even_a_single_edge_when_opted_in_and_never_when_off
    %w[on down].each do |mode|
      _, l = layout(%(component "a" { }\ncomponent "b" { }\na -> b\n), mode)

      assert_operator l.boxes["a"].bottom, :<, l.boxes["b"].top, mode
    end
    grouped = %(group "g" {\n ranks "on"\n component "a" { }\n component "b" { }\n}\na -> b\n)
    _, g = layout(grouped)

    assert_operator g.boxes["a"].bottom, :<, g.boxes["b"].top
    off_graph, off = layout(%(ranks "off"\n#{File.read(File.join(EXAMPLES, "dag.asd"))}))

    refute(off_graph.edges.all? { |e| off.boxes[e.from.id].bottom < off.boxes[e.to.id].top })
  end

  def test_ranks_a_group_left_to_right_for_right
    source = <<~SRC
      group "g" {
        ranks "right"
        component "a" { }
        component "b" { }
        component "c" { }
      }
      a -> b
      b -> c
    SRC
    _, l = layout(source)

    assert_operator l.boxes["a"].right, :<, l.boxes["b"].left
    assert_operator l.boxes["b"].right, :<, l.boxes["c"].left
    assert_in_delta l.boxes["a"].y, l.boxes["c"].y, 1e-9
  end

  def test_ranks_a_layer_left_to_right_and_a_stack_top_to_bottom_for_on_equal_ranks_side_by_side
    { "layer" => :right, "stack" => :down }.each do |kind, direction|
      source = <<~SRC
        #{kind} "g" {
          ranks "on"
          component "a" { }
          component "b" { }
          component "c" { }
        }
        a -> b
        a -> c
      SRC
      _, l = layout(source)
      a, b, c = %w[a b c].map { |id| l.boxes[id] }

      if direction == :right
        assert_operator a.right, :<, [b.left, c.left].min
        assert_operator b.bottom, :<=, c.top # same rank: one above the other
      else
        assert_operator a.bottom, :<, [b.top, c.top].min
        assert_operator b.right, :<=, c.left # same rank: side by side
      end
    end
  end

  def test_keeps_a_layer_or_stack_in_its_declared_order_under_auto
    source = %(stack "s" {\n component "a" { }\n component "b" { }\n component "c" { }\n}\nc -> b\nb -> a\n)
    _, l = layout(source)

    assert_operator l.boxes["a"].bottom, :<=, l.boxes["b"].top
    assert_operator l.boxes["b"].bottom, :<=, l.boxes["c"].top
  end

  def test_puts_an_interface_above_its_implementers
    source = %(ranks "down"\ncomponent "iface" { }\ncomponent "impl" { }\ncomponent "user" { }\nimpl -> iface { relation "implements" }\nuser -> impl\n)
    _, l = layout(source)

    assert_operator l.boxes["iface"].bottom, :<, l.boxes["impl"].top
    assert_operator l.boxes["user"].bottom, :<, l.boxes["impl"].top
  end

  def test_still_ranks_a_cycle_when_asked_but_never_under_auto
    cycle = %(component "a" { }\ncomponent "b" { }\ncomponent "c" { }\ncomponent "d" { }\na -> b\nb -> c\nc -> d\nd -> a\n)
    _, forced = layout(%(ranks "down"\n#{cycle}))
    ys = %w[a b c d].map { |id| forced.boxes[id].y }

    assert_equal ys.sort, ys # the one back edge (d -> a) reversed; the rest reads top to bottom
    assert_equal positions(layout(cycle, "off")), positions(layout(cycle))
  end

  def test_orders_each_rank_to_cross_fewer_edges_than_declaration_order_would
    # Declared so that a straight declaration-order layout crosses both
    # pairs of edges.
    source = <<~SRC
      ranks "down"
      component "a" { }
      component "b" { }
      component "x" { }
      component "y" { }
      component "p" { }
      component "q" { }
      a -> y
      b -> x
      x -> q
      y -> p
    SRC
    graph, l = layout(source)

    assert_equal 0, crossings(graph, l)
  end

  def test_ranks_containers_at_every_level_of_the_nested_example
    graph, l = layout(File.read(File.join(EXAMPLES, "dag_nested.asd")))

    %w[frontend services data platform].each_cons(2) do |upper, lower|
      assert_operator l.boxes[upper].bottom, :<, l.boxes[lower].top
    end
    %w[gateway orders payments events].each_cons(2) { |a, b| assert_operator l.boxes[a].bottom, :<, l.boxes[b].top }
    %w[ingest clean enrich store].each_cons(2) { |a, b| assert_operator l.boxes[a].right, :<, l.boxes[b].left }
    assert_in_delta l.boxes["db"].y, l.boxes["queue"].y, 1e-9 # the ranked stack's shared first rank
    assert_empty overlapping(l, graph.nodes_by_id.values.select(&:leaf?).map(&:id))
  end

  def test_parses_the_ranks_attribute_and_statement_and_rejects_unknown_modes
    graph, = layout(%(ranks "right"\ngroup "g" { ranks "off"\n component "a" { } }\n))

    assert_equal "right", graph.ranks_mode
    assert_equal "off", graph.nodes_by_id["g"].ranks_mode
    assert_equal "auto", graph.nodes_by_id["a"].ranks_mode

    attr = assert_raises(Archsight::Diagram::GraphError) { layout(%(group "g" {\n ranks "sideways"\n}\n)) }

    assert_equal 'unknown ranks "sideways" (line 1); expected one of auto, on, down, right, off', attr.message
    twice = assert_raises(Archsight::Diagram::GraphError) { layout(%(ranks "on"\nranks "off"\n)) }

    assert_equal "ranks already set at line 1 (line 2)", twice.message
  end

  private

  def layout(source, top = nil)
    source = %(ranks "#{top}"\n#{source}) if top
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    [graph, Archsight::Diagram::Layout.compute(graph, legend: "none")]
  end

  def positions((graph, layout)) = graph.nodes_by_id.keys.to_h { |id| [id, layout.boxes[id].to_a] }

  def overlapping(layout, ids)
    ids.combination(2).select do |a, b|
      x = layout.boxes[a]
      y = layout.boxes[b]
      x.left < y.right && y.left < x.right && x.top < y.bottom && y.top < x.bottom
    end
  end

  # Straight center-to-center segments crossing each other.
  def crossings(graph, layout)
    segments = graph.edges.map { |e| [layout.boxes[e.from.id], layout.boxes[e.to.id]].map { |b| [b.x, b.y] } }
    segments.combination(2).count do |(p1, p2), (q1, q2)|
      next false if [p1, p2].intersect?([q1, q2])

      d = ->(a, b, c) { ((b[0] - a[0]) * (c[1] - a[1])) - ((b[1] - a[1]) * (c[0] - a[0])) }
      (d.call(p1, p2, q1) * d.call(p1, p2, q2)).negative? && (d.call(q1, q2, p1) * d.call(q1, q2, p2)).negative?
    end
  end
end
