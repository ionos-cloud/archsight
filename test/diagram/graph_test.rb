# frozen_string_literal: true

require_relative "../test_helper"

class DiagramGraphTest < Minitest::Test
  def test_builds_a_containment_tree_and_resolves_edges
    source = <<~SRC
      group "vpc" {
        component "a" { label "A" }
        component "b" { label "B" }
        a -> b
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))

    vpc = graph.roots.first

    assert_equal "vpc", vpc.id
    assert_equal %w[a b], vpc.children.map(&:id)
    assert_equal vpc, vpc.children.first.parent

    edge = graph.edges.first

    assert_equal "a", edge.from.id
    assert_equal "b", edge.to.id
  end

  def test_raises_on_duplicate_ids
    source = <<~SRC
      component "a" { }
      component "a" { }
    SRC
    error = assert_raises(Archsight::Diagram::GraphError) { Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source)) }
    assert_match(/duplicate id/, error.message)
  end

  def test_raises_when_an_edge_references_an_unknown_id
    error = assert_raises(Archsight::Diagram::GraphError) { Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse("a -> b\n")) }
    assert_match(/unknown id "a"/, error.message)
  end

  def test_defaults_an_edge_s_style_to_straight_and_exposes_its_label
    source = <<~SRC
      component "a" { }
      component "b" { }
      a -> b { label "calls" }
    SRC
    edge = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source)).edges.first

    assert_equal "straight", edge.style
    assert_equal "calls", edge.label
  end

  def test_falls_back_to_the_id_when_a_node_has_no_label
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(%(component "a" { }\n)))

    assert_equal "a", graph.node("a").label
  end

  def test_defaults_each_leaf_keyword_s_shape_and_allows_an_explicit_shape_override
    source = <<~SRC
      component "comp" { }
      application "app" { }
      api "endpoint" { }
      database "db" { }
      queue "q" { }
      actor "user" { }
      component "overridden" { shape "cylinder" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))

    assert_equal "rectangle", graph.node("comp").shape
    assert_equal "rectangle", graph.node("app").shape
    assert_equal "circle", graph.node("endpoint").shape
    assert_equal "cylinder", graph.node("db").shape
    assert_equal "pipe", graph.node("q").shape
    assert_equal "actor", graph.node("user").shape
    assert_equal "cylinder", graph.node("overridden").shape
  end

  def test_treats_file_as_a_first_class_leaf_keyword_defaulting_to_the_file_shape_and_yellow_tint
    source = <<~SRC
      file "cfg" { label "Config" }
      component "same_via_shape" { shape "file" }
      file "tinted" { tint "blue" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))

    cfg = graph.node("cfg")

    assert_same true, cfg.leaf?
    assert_equal "file", cfg.shape
    assert_equal "yellow", cfg.effective_tint
    # renders identically to the older `shape "file"` spelling.
    assert_equal "yellow", graph.node("same_via_shape").effective_tint
    # an explicit tint still overrides the shape's own default.
    assert_equal "blue", graph.node("tinted").effective_tint
  end

  def test_distinguishes_application_from_component_even_though_both_render_as_rectangles
    source = <<~SRC
      component "comp" { }
      application "app" { }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))

    assert_same false, graph.node("comp").application?
    assert_same true, graph.node("app").application?
  end

  def test_gives_each_kind_its_own_default_tint_overridden_by_an_explicit_tint_or_by_shape_file
    source = <<~SRC
      component "comp" { }
      application "app" { }
      api "endpoint" { }
      database "db" { }
      queue "q" { }
      actor "user" { }
      group "g" { }
      boundary "b" { }
      component "cfg" { shape "file" }
      component "custom" { tint "green" }
      database "custom_db" { tint "green"; shape "file" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))

    assert_equal "blue", graph.node("comp").effective_tint
    assert_equal "teal", graph.node("app").effective_tint
    assert_equal "cyan", graph.node("endpoint").effective_tint
    assert_equal "purple", graph.node("db").effective_tint
    assert_equal "pink", graph.node("q").effective_tint
    assert_equal "gray", graph.node("user").effective_tint
    assert_equal "gray", graph.node("g").effective_tint
    assert_equal "red", graph.node("b").effective_tint
    assert_equal "yellow", graph.node("cfg").effective_tint
    assert_equal "green", graph.node("custom").effective_tint
    # an explicit tint attr wins even over the shape "file" default
    assert_equal "green", graph.node("custom_db").effective_tint
  end

  def test_doesn_t_inherit_tint_from_an_ancestor_but_darkens_nested_boxes_that_share_the_same_effective_tint
    source = <<~SRC
      group "outer" {
        tint "green"
        group "middle" {
          tint "green"
          group "inner" { }
        }
        group "sibling" { tint "purple" }
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))

    outer = graph.node("outer")
    middle = graph.node("middle")
    inner = graph.node("inner")
    sibling = graph.node("sibling")

    assert_equal 0, outer.tint_depth
    assert_equal 1, middle.tint_depth
    # "inner" isn't explicitly tinted, so it falls back to group's plain
    # default ("gray"), not "green" -- tint doesn't cascade down.
    assert_equal "gray", inner.effective_tint
    assert_equal 0, inner.tint_depth
    # "sibling" has its own, different tint, so it doesn't darken relative
    # to "outer" even though it's nested one level inside it.
    assert_equal "purple", sibling.effective_tint
    assert_equal 0, sibling.tint_depth
  end

  def test_skips_an_anonymous_layer_stack_when_counting_tint_depth_since_it_never_renders_a_box
    source = <<~SRC
      boundary "outer" {
        tint "blue"
        layer {
          group "inner" { tint "blue" }
          group "different" { tint "green" }
        }
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))

    # "inner" shares "outer"'s tint, with only an anonymous (never
    # rendered) layer in between -- it should still count as one level
    # deeper, not reset to 0.
    assert_equal 1, graph.node("inner").tint_depth
    # a genuinely different tint across that same anonymous layer still
    # doesn't darken, regardless of the anonymous ancestor.
    assert_equal 0, graph.node("different").tint_depth
  end

  def test_defaults_an_edge_s_relation_to_dependency_and_reads_an_explicit_relation
    source = <<~SRC
      component "a" { }
      component "b" { }
      a -> b { relation "implements" }
    SRC
    edge = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source)).edges.first

    assert_equal "implements", edge.relation
  end

  def test_treats_layer_stack_boundary_as_containers_but_not_leaves_alongside_group_leaf_keywords
    source = <<~SRC
      layer "l" { component "a" { } }
      stack "s" { component "b" { } }
      boundary "bd" { component "c" { } }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    %w[l s bd].each do |id|
      node = graph.node(id)

      assert_same true, node.container?
      assert_same false, node.leaf?
    end

    assert_same true, graph.node("a").leaf?
    assert_same false, graph.node("a").container?
  end

  def test_resolves_a_dataflow_s_hops_to_nodes_exposing_color_and_label
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      dataflow "flow" {
        hop "a"
        hop "b"
        hop "c"
        color "#2f855a"
        label "flows through"
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    df = graph.dataflows.first

    assert_equal "flow", df.id
    assert_equal %w[a b c], df.hops.map(&:id)
    assert_equal "#2f855a", df.color
    assert_equal "flows through", df.label
  end

  def test_raises_when_a_dataflow_hop_references_an_unknown_id
    source = <<~SRC
      component "a" { }
      dataflow "flow" { hop "a"; hop "missing" }
    SRC
    error = assert_raises(Archsight::Diagram::GraphError) { Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source)) }
    assert_match(/unknown id "missing".*dataflow "flow"/m, error.message)
  end

  def test_defaults_a_dataflow_s_color_label_to_nil_when_omitted
    source = <<~SRC
      component "a" { }
      component "b" { }
      dataflow "flow" { hop "a"; hop "b" }
    SRC
    df = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source)).dataflows.first

    assert_nil df.color
    assert_nil df.label
  end

  def test_resolves_a_hop_group_into_a_dataflowgroup_with_prefix_branches_suffix_nodes_and_merged_attrs
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      dataflow "flow" {
        hop "a"
        hop group {
          branch { hop "b"; label "active" }
          branch { hop "c"; label "passive" }
        }
        color "#C0392B"
      }
    SRC
    df = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source)).dataflows.first

    assert_equal [], df.hops
    assert_kind_of Archsight::Diagram::Graph::DataFlowGroup, df.group
    assert_equal %w[a], df.group.prefix.map(&:id)
    assert_equal [], df.group.suffix
    assert_equal([%w[b], %w[c]], df.group.branches.map { |b| b.hops.map(&:id) })
    assert_equal %w[active passive], df.group.branches.map(&:label)
    assert_equal ["#C0392B", "#C0392B"], df.group.branches.map(&:color)
  end

  def test_exposes_a_node_s_link_attribute_nil_when_absent
    source = <<~SRC
      component "a" { link "https://example.com" }
      component "b" { }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))

    assert_equal "https://example.com", graph.node("a").link
    assert_nil graph.node("b").link
  end

  def test_records_the_diagram_s_theme_name
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(%(theme "compact"\ncomponent "a" { }\n)))

    assert_equal "compact", graph.theme_name
  end

  def test_rejects_an_unknown_theme
    error = assert_raises(Archsight::Diagram::GraphError) do
      Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(%(theme "tiny"\n)))
    end

    assert_equal 'unknown theme "tiny" (line 1); expected one of default, cozy, compact', error.message
  end

  def test_rejects_a_second_theme_statement
    error = assert_raises(Archsight::Diagram::GraphError) do
      Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(%(theme "compact"\ntheme "default"\n)))
    end

    assert_equal "theme already set at line 1 (line 2)", error.message
  end
end
