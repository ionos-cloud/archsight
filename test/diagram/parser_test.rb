# frozen_string_literal: true

require_relative "../test_helper"

class DiagramParserTest < Minitest::Test
  def test_parses_a_flat_leaf_with_attributes
    stmts = Archsight::Diagram::Parser.parse(%(component "a" { label "A"; type "service" }\n))

    assert_equal 1, stmts.length
    block = stmts.first

    assert_kind_of Archsight::Diagram::AST::Block, block
    assert_equal :component, block.kind
    assert_equal "a", block.id
    assert_equal({ "label" => "A", "type" => "service" }, block.attrs)
    assert_equal [], block.children
  end

  def test_parses_each_leaf_keyword
    source = <<~SRC
      component "comp" { }
      application "app" { }
      api "endpoint" { }
      database "db" { }
      queue "q" { }
      actor "user" { }
      file "f" { }
    SRC
    kinds = Archsight::Diagram::Parser.parse(source).map(&:kind)

    assert_equal %i[component application api database queue actor file], kinds
  end

  def test_parses_nested_groups
    source = <<~SRC
      group "vpc" {
        label "VPC"
        component "a" { label "A" }
      }
    SRC
    block = Archsight::Diagram::Parser.parse(source).first

    assert_equal :group, block.kind
    assert_equal({ "label" => "VPC" }, block.attrs)
    assert_equal 1, block.children.length
    assert_equal "a", block.children.first.id
  end

  def test_parses_top_level_and_nested_edges
    source = <<~SRC
      group "g" {
        component "a" { }
        component "b" { }
        a -> b
      }
      c -> d
    SRC
    stmts = Archsight::Diagram::Parser.parse(source)
    top_level_edge = stmts.find { |s| s.is_a?(Archsight::Diagram::AST::Edge) }

    assert_equal "c", top_level_edge.from
    assert_equal "d", top_level_edge.to

    group = stmts.find { |s| s.is_a?(Archsight::Diagram::AST::Block) }
    nested_edge = group.children.find { |c| c.is_a?(Archsight::Diagram::AST::Edge) }

    assert_equal "a", nested_edge.from
    assert_equal "b", nested_edge.to
  end

  def test_parses_edge_attributes
    edge = Archsight::Diagram::Parser.parse(%(a -> b { style "orthogonal"; label "flows" }\n)).first

    assert_equal({ "style" => "orthogonal", "label" => "flows" }, edge.attrs)
  end

  def test_parses_layer_stack_and_boundary_blocks
    source = <<~SRC
      layer "l" { component "a" { } }
      stack "s" { component "b" { } }
      boundary "b" { component "c" { } }
    SRC
    kinds = Archsight::Diagram::Parser.parse(source).map(&:kind)

    assert_equal %i[layer stack boundary], kinds
  end

  def test_records_edge_direction_for_arrow_biarrow_and_undirected
    source = <<~SRC
      a -> b
      c <-> d
      e -- f
    SRC
    directions = Archsight::Diagram::Parser.parse(source).map(&:direction)

    assert_equal %i[directed bidirectional undirected], directions
  end

  def test_raises_a_helpful_error_for_a_bare_less_than_where_an_edge_arrow_is_expected
    assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse("a < b\n") }
  end

  def test_raises_a_helpful_error_for_an_unclosed_block
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(%(component "a" { label "A" \n)) }
    assert_match(/line 2/, error.message)
  end

  def test_raises_when_a_leaf_block_contains_nested_content
    source = <<~SRC
      component "a" {
        component "b" { }
      }
    SRC
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(source) }
    assert_match(/cannot contain nested blocks/, error.message)
  end

  def test_identifies_an_anonymous_layer_stack_by_its_opening_line_never_its_internal_synthetic_id
    source = <<~SRC
      layer {
        component "a" { }
        {
          component "b" { }
        }
      }
    SRC
    e = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(source) }
    assert_includes e.message, "opened at line 1"
    refute_includes e.message, "__asd_anon"
  end

  def test_gives_the_generic_unexpected_token_fallback_a_hint_for_a_stray_lbrace
    source = <<~SRC
      group "vpc" {
        {
          component "a" { }
        }
      }
    SRC
    e = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(source) }
    assert_match(/expected .*, or '}' to close group "vpc"/, e.message)
    assert_includes e.message, "a stray '{' usually means a missing keyword"
  end

  def test_gives_the_generic_unexpected_token_fallback_a_hint_for_a_bare_quoted_string
    source = <<~SRC
      group "vpc" {
        "oops" { label "x" }
      }
    SRC
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(source) }
    assert_match(/a bare quoted string here usually needs a keyword before it/, error.message)
  end

  def test_raises_the_standard_parse_error_for_the_removed_node_keyword
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(%(node "a" { }\n)) }
    assert_match(/expected/, error.message)
  end

  def test_parses_a_bare_reference_to_a_node_named_after_a_leaf_keyword_e_g_api_as_an_edge_not_a_new_block
    source = <<~SRC
      api "api" { }
      component "db" { }
      api -> db
    SRC
    stmts = Archsight::Diagram::Parser.parse(source)

    assert_equal 3, stmts.length
    edge = stmts.last

    assert_kind_of Archsight::Diagram::AST::Edge, edge
    assert_equal "api", edge.from
    assert_equal "db", edge.to
  end

  def test_raises_on_an_unexpected_top_level_token
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse("}\n") }
    assert_match(/expected/, error.message)
  end

  def test_parses_an_unnamed_layer_stack_as_anonymous_auto_generating_an_id
    source = <<~SRC
      stack {
        layer {
          component "a" { }
          component "b" { }
        }
      }
    SRC
    stack = Archsight::Diagram::Parser.parse(source).first

    assert_equal :stack, stack.kind
    assert_same true, stack.anonymous
    refute_nil stack.id

    layer = stack.children.first

    assert_equal :layer, layer.kind
    assert_same true, layer.anonymous
    refute_equal stack.id, layer.id
  end

  def test_still_requires_an_id_on_a_named_layer_stack
    block = Archsight::Diagram::Parser.parse(%(stack "s" { }\n)).first

    assert_same false, block.anonymous
    assert_equal "s", block.id
  end

  def test_raises_a_clear_error_for_an_unnamed_group_boundary_leaf_unlike_layer_stack
    %w[group boundary component].each do |keyword|
      error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(%(#{keyword} { }\n)) }
      assert_match(/requires a quoted id/, error.message)
    end
  end

  def test_parses_a_dataflow_s_hops_color_and_label
    source = <<~SRC
      dataflow "flow" {
        hop "a"
        hop "b"
        hop "c"
        color "#2f855a"
        label "flows through"
      }
    SRC
    df = Archsight::Diagram::Parser.parse(source).first

    assert_kind_of Archsight::Diagram::AST::DataFlow, df
    assert_equal "flow", df.id
    assert_equal %w[a b c], df.hops
    assert_equal({ "color" => "#2f855a", "label" => "flows through" }, df.attrs)
  end

  def test_parses_a_dataflow_with_no_color_label_just_hops
    df = Archsight::Diagram::Parser.parse(%(dataflow "flow" { hop "a"; hop "b" }\n)).first

    assert_equal %w[a b], df.hops
    assert_equal({}, df.attrs)
  end

  def test_raises_when_a_dataflow_has_fewer_than_2_hops
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(%(dataflow "flow" { hop "a" }\n)) }
    assert_match(/needs at least 2 hops/, error.message)
  end

  def test_parses_a_hop_group_with_bare_hop_branches
    source = <<~SRC
      dataflow "flow" {
        hop "a"
        hop group {
          hop "b"
          hop "c"
        }
        color "#8E44AD"
      }
    SRC
    df = Archsight::Diagram::Parser.parse(source).first

    assert_equal 2, df.hops.length
    assert_equal "a", df.hops.first
    group = df.hops.last

    assert_kind_of Archsight::Diagram::AST::DataFlowGroup, group
    assert_equal [["b"], ["c"]], group.branches.map(&:hops)
    assert_equal [{}, {}], group.branches.map(&:attrs)
  end

  def test_parses_a_hop_group_with_explicit_branch_blocks_and_a_per_branch_label_override
    source = <<~SRC
      dataflow "flow" {
        hop "a"
        hop group {
          branch { hop "b"; hop "d"; label "active" }
          branch { hop "c"; hop "e"; label "passive" }
        }
        color "#C0392B"
      }
    SRC
    group = Archsight::Diagram::Parser.parse(source).first.hops.last

    assert_equal [%w[b d], %w[c e]], group.branches.map(&:hops)
    assert_equal [{ "label" => "active" }, { "label" => "passive" }], group.branches.map(&:attrs)
  end

  def test_raises_when_a_hop_group_has_fewer_than_2_branches
    source = %(dataflow "flow" { hop "a"; hop group { hop "b" } }\n)
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(source) }
    assert_match(/needs at least 2 branches/, error.message)
  end

  def test_raises_when_a_branch_has_no_hops
    source = <<~SRC
      dataflow "flow" {
        hop "a"
        hop group {
          branch { label "x" }
          hop "b"
        }
      }
    SRC
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(source) }
    assert_match(/needs at least 1 hop/, error.message)
  end

  def test_raises_when_a_dataflow_has_more_than_one_hop_group
    source = <<~SRC
      dataflow "flow" {
        hop group { hop "a"; hop "b" }
        hop group { hop "c"; hop "d" }
      }
    SRC
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(source) }
    assert_match(/may only have one 'hop group'/, error.message)
  end

  def test_raises_when_a_hop_group_branch_s_effective_hop_count_is_below_two
    source = %(dataflow "flow" { hop group { hop "a"; hop "b" } }\n)
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(source) }
    assert_match(/needs at least 2 hops on every branch/, error.message)
  end

  def test_parses_a_bare_reference_to_a_node_named_dataflow_as_an_edge_not_a_new_dataflow
    source = <<~SRC
      component "dataflow" { }
      component "db" { }
      dataflow -> db
    SRC
    stmts = Archsight::Diagram::Parser.parse(source)
    edge = stmts.last

    assert_kind_of Archsight::Diagram::AST::Edge, edge
    assert_equal "dataflow", edge.from
    assert_equal "db", edge.to
  end

  def test_parses_no_gap_no_extend_as_sugar_for_gap_0_extend_false
    source = <<~SRC
      stack "s" {
        no-gap
        no-extend
        component "a" { }
      }
    SRC
    block = Archsight::Diagram::Parser.parse(source).first

    assert_equal({ "gap" => "0", "extend" => "false" }, block.attrs)
  end

  def test_parses_tint_as_a_plain_attr_same_as_label_shape_link
    block = Archsight::Diagram::Parser.parse(%(group "g" { tint "green" }\n)).first

    assert_equal({ "tint" => "green" }, block.attrs)
  end

  def test_parses_no_gap_no_extend_inside_a_dataflow_and_a_branch
    source = <<~SRC
      dataflow "flow" {
        no-gap
        hop "a"
        hop group {
          branch { hop "b"; no-extend }
          branch { hop "c" }
        }
      }
    SRC
    df = Archsight::Diagram::Parser.parse(source).first

    assert_equal({ "gap" => "0" }, df.attrs)
    group = df.hops.find { |h| h.is_a?(Archsight::Diagram::AST::DataFlowGroup) }

    assert_equal({ "extend" => "false" }, group.branches.first.attrs)
  end

  def test_treats_no_gap_no_extend_followed_by_a_string_as_a_literal_attr_not_the_bare_flag
    block = Archsight::Diagram::Parser.parse(%(stack "s" { no-gap "50" }\n)).first

    assert_equal({ "no-gap" => "50" }, block.attrs)
  end

  def test_expands_columns_into_an_anonymous_layer_of_column_major_anonymous_stacks
    source = <<~SRC
      stack "s" {
        columns "2"
        component "a" { }
        component "b" { }
        component "c" { }
        component "d" { }
        a -> c
      }
    SRC
    block = Archsight::Diagram::Parser.parse(source).first
    layer, edge = block.children

    assert_equal :layer, layer.kind
    assert_predicate layer, :anonymous?
    assert_equal [%i[stack stack], [true, true]], [layer.children.map(&:kind), layer.children.map(&:anonymous?)]
    assert_equal([%w[a b], %w[c d]], layer.children.map { |col| col.children.map(&:id) })

    # Edges only reference ids, so they stay direct children.
    assert_kind_of Archsight::Diagram::AST::Edge, edge
  end

  def test_gives_the_leading_columns_the_extra_cell_when_columns_don_t_divide_evenly
    source = <<~SRC
      stack "s" {
        columns "2"
        component "a" { }
        component "b" { }
        component "c" { }
        component "d" { }
        component "e" { }
      }
    SRC
    layer = Archsight::Diagram::Parser.parse(source).first.children.first

    assert_equal([%w[a b c], %w[d e]], layer.children.map { |col| col.children.map(&:id) })
  end

  def test_wraps_a_single_column_in_one_stack_like_any_other_column_count
    block = Archsight::Diagram::Parser.parse(%(layer "l" { columns "1"; component "a" { } component "b" { } component "c" { } }\n)).first
    layer = block.children.first

    assert_equal [:layer, [:stack]], [layer.kind, layer.children.map(&:kind)]
    assert_equal([%w[a b c]], layer.children.map { |col| col.children.map(&:id) })
  end

  def test_rejects_a_non_positive_integer_columns_value
    %w[0 x -1 2.5].each do |value|
      error = assert_raises(Archsight::Diagram::ParseError) do
        Archsight::Diagram::Parser.parse(%(stack "s" { columns "#{value}"; component "a" { } }\n))
      end
      assert_match(/columns must be a positive integer/, error.message)
    end
  end

  def test_rejects_columns_on_a_leaf
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(%(component "a" { columns "2" }\n)) }

    assert_match(/columns only applies to containers/, error.message)
  end

  def test_parses_a_top_level_theme_setting
    stmts = Archsight::Diagram::Parser.parse(%(theme "compact";\ncomponent "a" { }\n))

    setting = stmts.first

    assert_kind_of Archsight::Diagram::AST::Setting, setting
    assert_equal ["theme", "compact", 1], [setting.key, setting.value, setting.line]
  end

  def test_still_parses_a_node_named_theme_as_an_edge_endpoint
    stmts = Archsight::Diagram::Parser.parse(%(component "theme" { }\ncomponent "x" { }\ntheme -> x\n))

    assert_kind_of Archsight::Diagram::AST::Edge, stmts.last
    assert_equal "theme", stmts.last.from
  end

  def test_rejects_an_attribute_given_twice_in_one_block
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(%(component "a" {\n  label "x"\n  label "y"\n}\n)) }

    assert_equal %(duplicate attribute 'label' in component "a" at line 3), error.message
  end

  def test_rejects_a_flag_and_its_attribute_given_together_and_a_repeated_edge_or_dataflow_attribute
    assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(%(component "a" { gap "1"; no-gap }\n)) }
    edge = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(%(a -> b { style "straight"; style "orthogonal" }\n)) }
    flow = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Parser.parse(%(dataflow "f" { hop "a"; hop "b"; color "#fff"; color "#000" }\n)) }

    assert_match(/duplicate attribute 'style' in edge a -> b at line 1/, edge.message)
    assert_match(/duplicate attribute 'color' in dataflow "f"/, flow.message)
  end
end
