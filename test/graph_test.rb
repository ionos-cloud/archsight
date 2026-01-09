# frozen_string_literal: true

require "test_helper"

class GraphvisTest < Minitest::Test
  def setup
    @graph = Archsight::Graphvis.new("test_graph")
  end

  # value() method tests

  def test_value_with_regular_string
    assert_equal '"hello"', @graph.value("hello")
  end

  def test_value_with_html_like_string
    # HTML-like values (wrapped in <>) get double-wrapped
    assert_equal "<<table>>", @graph.value("<table>")
  end

  def test_value_with_symbol
    assert_equal '"LR"', @graph.value(:LR)
  end

  def test_value_with_number
    assert_equal '"42"', @graph.value(42)
  end

  # draw_dot() tests

  def test_draw_dot_basic
    dot = @graph.draw_dot { |_g| nil }

    assert_includes dot, "digraph G {"
    assert_includes dot, "}"
    assert_includes dot, '"rankdir"'
  end

  def test_draw_dot_with_node
    dot = @graph.draw_dot do |g|
      g.node("test_node", label: "Test")
    end

    assert_includes dot, '"test_node"'
    assert_includes dot, '"label"'
    assert_includes dot, '"Test"'
  end

  def test_draw_dot_with_edge
    dot = @graph.draw_dot do |g|
      g.edge("node_a", "node_b", style: "dashed")
    end

    assert_includes dot, '"node_a" -> "node_b"'
    assert_includes dot, '"style"'
    assert_includes dot, '"dashed"'
  end

  # subgraph() tests

  def test_subgraph
    dot = @graph.draw_dot do |g|
      g.subgraph("cluster_0", label: "Cluster") do |sg|
        sg.node("inner_node")
      end
    end

    assert_includes dot, 'subgraph "cluster_0"'
    assert_includes dot, '"label"'
    assert_includes dot, '"inner_node"'
  end

  # same_rank() tests

  def test_same_rank
    dot = @graph.draw_dot do |g|
      g.same_rank do |sr|
        sr.node("node1")
        sr.node("node2")
      end
    end

    assert_includes dot, "{ rank = same;"
    assert_includes dot, '"node1"'
    assert_includes dot, '"node2"'
  end

  # node() and edge() with multiple attributes

  def test_node_with_multiple_attributes
    dot = @graph.draw_dot do |g|
      g.node("multi", label: "Label", shape: "box", color: "red")
    end

    assert_includes dot, '"label"'
    assert_includes dot, '"shape"'
    assert_includes dot, '"color"'
  end

  def test_edge_with_multiple_attributes
    dot = @graph.draw_dot do |g|
      g.edge("a", "b", label: "connects", style: "bold", color: "blue")
    end

    assert_includes dot, '"a" -> "b"'
    assert_includes dot, '"label"'
    assert_includes dot, '"style"'
    assert_includes dot, '"color"'
  end

  # Custom graph attributes

  def test_graph_with_custom_attrs
    graph = Archsight::Graphvis.new("custom", :dot, rankdir: :TB, splines: :ortho)
    dot = graph.draw_dot { |_g| nil }

    assert_includes dot, '"rankdir" = "TB"'
    assert_includes dot, '"splines" = "ortho"'
  end
end

class GraphvisHelperTest < Minitest::Test
  include Archsight::GraphvisHelper

  def test_graphviz_svg_generates_javascript
    result = graphviz_svg("digraph { a -> b }", "graph-container")

    assert_includes result, "<script type=\"module\">"
    assert_includes result, "Graphviz.load()"
    assert_includes result, "digraph { a -> b }"
    assert_includes result, "graph-container"
  end

  def test_graphviz_svg_escapes_dot_content
    result = graphviz_svg('digraph { label="test\nvalue" }', "el")

    assert_includes result, "digraph"
    # The dot content should be properly escaped in JavaScript
    assert_includes result, "const dot ="
  end

  def test_graphviz_svg_includes_css_fetch
    result = graphviz_svg("digraph {}", "id")

    assert_includes result, "fetch(\"/css/graph.css?"
    assert_includes result, "cssResponse.text()"
  end

  def test_graphviz_svg_dispatches_ready_event
    result = graphviz_svg("digraph {}", "my-graph")

    assert_includes result, "graphviz:ready"
    assert_includes result, "my-graph"
  end
end
