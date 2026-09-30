# frozen_string_literal: true

require_relative "../test_helper"

class DiagramStylesheetTest < Minitest::Test
  def test_defines_every_tint_s_fill_stroke_class_at_every_shade_level_and_every_relation_s_class
    block = stylesheet_for(%(component "a" { }\n)).style_block

    Archsight::Diagram::Tints.names.each do |name|
      tint = Archsight::Diagram::Tints.for(name)
      (0..Archsight::Diagram::Tint::MAX_SHADE_LEVEL).each do |level|
        assert_includes block, ".#{tint.fill_class(level)} { fill: #{tint.fill(level)}; }"
        assert_includes block, ".#{tint.border_class(level)} { stroke: #{tint.border(level)}; }"
      end
    end

    Archsight::Diagram::Relations.names.each do |name|
      assert_includes block, ".asd-relation-#{name} {"
    end
  end

  def test_generates_one_dataflow_color_rule_per_distinct_color_actually_used_none_for_a_diagram_with_no_dataflow_colors
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      dataflow "flow1" { hop "a"; hop "b"; color "#ff8800" }
      dataflow "flow2" { hop "b"; hop "c"; color "#ff8800" }
    SRC
    block = stylesheet_for(source).style_block

    assert_equal 1, block.scan(".asd-relation-data.asd-dataflow-color-ff8800").length

    plain_block = stylesheet_for(%(component "a" { }\n)).style_block

    refute_includes plain_block, "asd-dataflow-color-"
  end

  def test_generates_one_stroke_override_rule_per_distinct_relation_tint_pair_used_by_a_tinted_edge
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      a -> b { tint "purple" }
      a -> c { relation "implements"; tint "purple" }
    SRC
    block = stylesheet_for(source).style_block
    purple = Archsight::Diagram::Tints.for("purple")
    slug = Archsight::Diagram::Renderer::MarkerDefs.color_class(purple.border(0))

    # Same tint, two different relations -- each still needs its own
    # compound rule since it overrides a different base relation class.
    assert_includes block, ".asd-relation-dependency.#{slug} { stroke: #{purple.border(0)}; }"
    assert_includes block, ".asd-relation-implements.#{slug} { stroke: #{purple.border(0)}; }"
  end

  def test_keeps_hover_has_interaction_rules_out_of_style_block_in_interaction_style_block_instead
    stylesheet = stylesheet_for(%(component "a" { }\n))

    refute_includes stylesheet.style_block, ".asd-link"
    assert_includes stylesheet.interaction_style_block, ".asd-link"
    refute_includes stylesheet.interaction_style_block, ".asd-fs-13"
  end

  def test_generates_a_legend_hover_has_rule_per_authored_dataflow_in_interaction_style_block
    source = <<~SRC
      component "a" { }
      component "b" { }
      dataflow "flow" { hop "a"; hop "b" }
    SRC
    block = stylesheet_for(source).interaction_style_block

    assert_includes block, 'svg:has(.asd-legend-dataflow[data-dataflow="flow"]:hover)'
  end

  HIGHLIGHT = "stroke-width: 3.0; marker-start: var(--asd-hover-marker-start); marker-end: var(--asd-hover-marker-end);"

  def test_swaps_a_highlighted_line_s_arrowhead_for_a_slightly_bigger_twin_rather_than_doubling_it
    css = Archsight::Diagram.render(%(component "a" { }\ncomponent "b" { }\na -> b\n))

    assert_includes css, '.asd-line[marker-end="url(#arrow-dependency)"] { --asd-hover-marker-end: url(#arrow-dependency-hover); }'
    # 7 stroke widths at 1.5px is 10.5px on screen; the twin, at the 3px
    # hover width, is 1.25 times that: 13.125px, i.e. 4.375 stroke widths.
    assert_includes css, '<marker id="arrow-dependency-hover" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="4.375" markerHeight="4.375"'
  end

  HOVER_SOURCE = <<~SRC
    group "g" {
      component "a" { }
      component "b" { }
    }
    component "c" { }
    a -> b { label "x" }
    a -> c
    b -> c
    g -> c
  SRC

  def test_highlights_a_leaf_s_outgoing_edges_while_it_or_its_label_is_hovered
    css = Archsight::Diagram.render(HOVER_SOURCE)

    assert_includes css, "svg:has(#asd-node-a:hover,#asd-node-a__label:hover) " \
                         ":is(#asd-edge-a__b,#asd-edge-a__c,#asd-edge-a__b__label,#asd-edge-a__c__label) { opacity: 1; font-weight: bold; }"
    assert_includes css, "svg:has(#asd-node-a:hover,#asd-node-a__label:hover) :is(#asd-edge-a__b,#asd-edge-a__c) .asd-line { #{HIGHLIGHT} }"
    refute_includes css, "#asd-node-c:hover" # no outgoing edges, nothing to highlight
  end

  def test_highlights_a_container_s_own_edges_only_from_its_frame_not_its_whole_group
    css = Archsight::Diagram.render(HOVER_SOURCE)

    # Its <g> also holds a's and b's, so hovering either child would
    # otherwise light up the container's edges too.
    assert_includes css, "svg:has(#asd-node-g__frame:hover,#asd-node-g__label:hover) :is(#asd-edge-g__c,#asd-edge-g__c__label)"
    refute_includes css, "#asd-node-g:hover"
  end

  def test_ties_an_edge_to_its_label_but_leaves_an_unlabelled_one_to_the_generic_hover_rule
    css = Archsight::Diagram.render(HOVER_SOURCE)

    assert_includes css, "svg:has(#asd-edge-a__b:hover,#asd-edge-a__b__label:hover) :is(#asd-edge-a__b,#asd-edge-a__b__label)"
    assert_includes css, "svg:has(#asd-edge-a__b__label:hover) #asd-edge-a__b .asd-line"
    refute_includes css, "svg:has(#asd-edge-b__c:hover"
    assert_includes css, "svg:has(.asd-edge:hover) .asd-edge:hover { opacity: 1; }"
    assert_includes css, "svg:has(.asd-edge:hover, .asd-edge-label:hover, .asd-hover-source:hover) :is(.asd-edge, .asd-edge-label, " \
                         ".asd-tree-line, .asd-dataflow, .asd-dataflow-label) { opacity: 0.2; }"
  end

  def test_lights_up_an_implements_tree_s_spine_and_trunk_with_any_of_its_stubs
    source = <<~SRC
      component "t" { }
      component "i1" { }
      component "i2" { }
      i1 -> t { relation "implements" }
      i2 -> t { relation "implements" }
    SRC
    css = Archsight::Diagram.render(source)

    assert_includes css, "svg:has(#asd-edge-i1__t:hover) :is(#asd-tree-t__spine,#asd-tree-t__trunk) { opacity: 1; font-weight: bold; }"
    assert_includes css, "svg:has(#asd-edge-i2__t:hover) :is(#asd-tree-t__spine,#asd-tree-t__trunk) { #{HIGHLIGHT} }"
  end

  def test_generates_hover_rules_only_for_drawn_edges_and_even_without_the_presentation_stylesheet
    source = %(component "a" { }\ncomponent "b" { }\na -> b { relation "control"; label "ctl" }\n)

    refute_includes Archsight::Diagram.render(source), "#asd-edge-a__b"
    all = Archsight::Diagram.render(source, relation_filter: Archsight::Diagram::Relations.names, style: "none")

    assert_includes all, "svg:has(#asd-edge-a__b:hover,#asd-edge-a__b__label:hover)"
    assert_includes all, ".asd-hit { fill: none; stroke: transparent;"
  end

  def test_emits_one_font_size_rule_per_size_the_theme_renders_at
    graph = graph_for(%(component "a" { }\n))
    drawn = Archsight::Diagram::Renderer::DrawnEdges.new(graph.edges)
    default_block = Archsight::Diagram::Renderer::Stylesheet.new(graph, drawn).style_block
    compact_block = Archsight::Diagram::Renderer::Stylesheet.new(graph, drawn, theme: Archsight::Diagram::Theme::COMPACT).style_block

    assert_equal %w[11 12 13 15], default_block.scan(/\.asd-fs-(\d+) \{ font-size: \1px; \}/).flatten
    assert_equal %w[10 11 12 13], compact_block.scan(/\.asd-fs-(\d+) \{ font-size: \1px; \}/).flatten
    cozy_block = Archsight::Diagram::Renderer::Stylesheet.new(graph, drawn, theme: Archsight::Diagram::Theme::COZY).style_block

    assert_equal %w[11 12 14], cozy_block.scan(/\.asd-fs-(\d+) \{ font-size: \1px; \}/).flatten
  end

  private

  def graph_for(source)
    Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
  end

  def stylesheet_for(source)
    graph = graph_for(source)
    Archsight::Diagram::Renderer::Stylesheet.new(graph, Archsight::Diagram::Renderer::DrawnEdges.new(graph.edges))
  end
end
