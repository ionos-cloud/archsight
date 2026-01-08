# frozen_string_literal: true

require_relative "../test_helper"

class ParserTest < Minitest::Test
  def parse(source)
    Archsight::Query.parse(source).ast
  end

  # Kind filter tests
  def test_kind_filter
    ast = parse('TechnologyArtifact: foo == "bar"')

    assert_equal "TechnologyArtifact", ast.kind_filter
  end

  def test_no_kind_filter
    ast = parse('foo == "bar"')

    assert_nil ast.kind_filter
  end

  # Annotation condition tests
  def test_simple_annotation_condition
    ast = parse('activity/status == "active"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr
    assert_equal "activity/status", expr.path
    assert_equal "==", expr.operator
    assert_instance_of Archsight::Query::AST::StringValue, expr.value
    assert_equal "active", expr.value.value
  end

  def test_numeric_comparison
    ast = parse("scc/loc > 1000")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr
    assert_equal "scc/loc", expr.path
    assert_equal ">", expr.operator
    assert_instance_of Archsight::Query::AST::NumberValue, expr.value
    assert_in_delta(1000.0, expr.value.value)
  end

  def test_not_equals
    ast = parse('status != "abandoned"')
    expr = ast.expression

    assert_equal "!=", expr.operator
  end

  def test_regex_match
    ast = parse('name =~ "test.*"')
    expr = ast.expression

    assert_equal "=~", expr.operator
  end

  # Kind condition tests
  def test_kind_condition
    ast = parse('kind == "TechnologyArtifact"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::KindCondition, expr
    assert_equal "==", expr.operator
    assert_equal "TechnologyArtifact", expr.value.value
  end

  # Name condition tests
  def test_name_equals
    ast = parse('name == "MyService"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NameCondition, expr
    assert_equal "==", expr.operator
    assert_equal "MyService", expr.value.value
  end

  def test_name_not_equals
    ast = parse('name != "OldService"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NameCondition, expr
    assert_equal "!=", expr.operator
  end

  def test_name_regex
    ast = parse('name =~ "kubernetes.*"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NameCondition, expr
    assert_equal "=~", expr.operator
    assert_equal "kubernetes.*", expr.value.value
  end

  def test_name_shortcut
    ast = parse("kubernetes")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NameCondition, expr
    assert_equal "=~", expr.operator
    assert_equal "kubernetes", expr.value.value
  end

  # Annotation existence tests
  def test_annotation_exists_condition
    ast = parse("activity/status?")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationExistsCondition, expr
    assert_equal "activity/status", expr.path
  end

  def test_annotation_exists_with_deep_path
    ast = parse("scc/language/Go/loc?")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationExistsCondition, expr
    assert_equal "scc/language/Go/loc", expr.path
  end

  # Quoted annotation path tests
  def test_quoted_annotation_path_comparison
    ast = parse("'scc/language/C++/loc' >= 500")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr
    assert_equal "scc/language/C++/loc", expr.path
    assert_equal ">=", expr.operator
    assert_instance_of Archsight::Query::AST::NumberValue, expr.value
    assert_in_delta(500.0, expr.value.value)
  end

  def test_quoted_annotation_path_existence
    ast = parse("'scc/language/C++/loc'?")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationExistsCondition, expr
    assert_equal "scc/language/C++/loc", expr.path
  end

  def test_quoted_annotation_path_in_combined_query
    ast = parse("TechnologyArtifact: activity/status == \"active\" & 'scc/language/C++/loc' >= 500")
    expr = ast.expression

    assert_equal "TechnologyArtifact", ast.kind_filter
    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.left
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.right
    assert_equal "scc/language/C++/loc", expr.right.path
  end

  def test_annotation_exists_negated
    ast = parse("! activity/status?")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NotOp, expr
    assert_instance_of Archsight::Query::AST::AnnotationExistsCondition, expr.operand
    assert_equal "activity/status", expr.operand.path
  end

  def test_annotation_exists_combined_with_and
    ast = parse('activity/status? & repository/artifacts == "container"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::AnnotationExistsCondition, expr.left
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.right
  end

  def test_annotation_exists_vs_name_shortcut
    # Without ? = name shortcut
    ast = parse("kubernetes")

    assert_instance_of Archsight::Query::AST::NameCondition, ast.expression

    # With ? = annotation exists
    ast = parse("kubernetes?")

    assert_instance_of Archsight::Query::AST::AnnotationExistsCondition, ast.expression
  end

  def test_name_shortcut_combined
    ast = parse('kubernetes & activity/status == "active"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::NameCondition, expr.left
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.right
  end

  def test_name_shortcut_with_kind_filter
    ast = parse("TechnologyArtifact: repo")

    assert_equal "TechnologyArtifact", ast.kind_filter
    assert_instance_of Archsight::Query::AST::NameCondition, ast.expression
    assert_equal "repo", ast.expression.value.value
  end

  def test_kind_filter_alone
    ast = parse("TechnologyArtifact:")

    assert_equal "TechnologyArtifact", ast.kind_filter
    assert_nil ast.expression
  end

  # Logical operator tests
  def test_and_expression
    ast = parse('foo == "a" & bar == "b"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.left
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.right
  end

  def test_or_expression
    ast = parse('foo == "a" | bar == "b"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :or, expr.operator
  end

  def test_not_expression
    ast = parse('! foo == "a"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NotOp, expr
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.operand
  end

  def test_lowercase_and
    ast = parse('foo == "a" and bar == "b"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
  end

  def test_uppercase_and
    ast = parse('foo == "a" AND bar == "b"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
  end

  def test_lowercase_or
    ast = parse('foo == "a" or bar == "b"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :or, expr.operator
  end

  def test_uppercase_or
    ast = parse('foo == "a" OR bar == "b"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :or, expr.operator
  end

  def test_lowercase_not
    ast = parse('not foo == "a"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NotOp, expr
  end

  def test_uppercase_not
    ast = parse('NOT foo == "a"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NotOp, expr
  end

  # Operator precedence tests
  def test_and_higher_precedence_than_or
    # a | b & c should parse as a | (b & c)
    ast = parse('a == "1" | b == "2" & c == "3"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :or, expr.operator
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.left
    assert_instance_of Archsight::Query::AST::BinaryOp, expr.right
    assert_equal :and, expr.right.operator
  end

  def test_not_higher_precedence_than_and
    # ! a & b should parse as (! a) & b
    ast = parse('! a == "1" & b == "2"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::NotOp, expr.left
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.right
  end

  def test_parentheses_override_precedence
    # (a | b) & c
    ast = parse('(a == "1" | b == "2") & c == "3"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::BinaryOp, expr.left
    assert_equal :or, expr.left.operator
  end

  # Relation tests
  def test_outgoing_direct_relation_kind
    ast = parse("-> ApplicationInterface")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::KindTarget, expr.target
    assert_equal "ApplicationInterface", expr.target.kind_name
  end

  def test_outgoing_direct_relation_instance
    ast = parse('-> "Kubernetes:RestAPI"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::InstanceTarget, expr.target
    assert_equal "Kubernetes:RestAPI", expr.target.instance_name
  end

  def test_outgoing_transitive_relation
    ast = parse("~> BusinessRequirement")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingTransitiveRelation, expr
    assert_instance_of Archsight::Query::AST::KindTarget, expr.target
  end

  def test_incoming_direct_relation
    ast = parse("<- ApplicationComponent")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::IncomingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::KindTarget, expr.target
  end

  def test_incoming_transitive_relation
    ast = parse("<~ BusinessProduct")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::IncomingTransitiveRelation, expr
    assert_instance_of Archsight::Query::AST::KindTarget, expr.target
  end

  # Combined query tests
  def test_annotation_and_relation
    ast = parse('activity/status == "active" & -> ApplicationInterface')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.left
    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr.right
  end

  def test_kind_filter_with_annotation
    ast = parse('TechnologyArtifact: activity/status == "active"')

    assert_equal "TechnologyArtifact", ast.kind_filter
    assert_instance_of Archsight::Query::AST::AnnotationCondition, ast.expression
  end

  def test_complex_combined_query
    ast = parse('ApplicationComponent: ~> "C5-2020:A-5-9" & repository/artifacts == "container"')

    assert_equal "ApplicationComponent", ast.kind_filter
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::OutgoingTransitiveRelation, expr.left
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.right
  end

  # Subquery tests
  def test_subquery_target_with_name_shortcut
    ast = parse("-> $(kubernetes)")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::SubqueryTarget, expr.target
    inner = expr.target.query

    assert_nil inner.kind_filter
    assert_instance_of Archsight::Query::AST::NameCondition, inner.expression
    assert_equal "kubernetes", inner.expression.value.value
  end

  def test_subquery_target_with_kind_filter
    ast = parse("-> $(TechnologyArtifact:)")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::SubqueryTarget, expr.target
    inner = expr.target.query

    assert_equal "TechnologyArtifact", inner.kind_filter
    assert_nil inner.expression
  end

  def test_subquery_target_with_kind_filter_and_expression
    ast = parse('~> $(TechnologyArtifact: activity/status == "active")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingTransitiveRelation, expr
    assert_instance_of Archsight::Query::AST::SubqueryTarget, expr.target
    inner = expr.target.query

    assert_equal "TechnologyArtifact", inner.kind_filter
    assert_instance_of Archsight::Query::AST::AnnotationCondition, inner.expression
  end

  def test_subquery_target_incoming
    ast = parse('<- $(name == "MyService")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::IncomingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::SubqueryTarget, expr.target
    inner = expr.target.query

    assert_instance_of Archsight::Query::AST::NameCondition, inner.expression
    assert_equal "==", inner.expression.operator
  end

  def test_subquery_target_transitive_incoming
    ast = parse("<~ $(-> ApplicationInterface)")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::IncomingTransitiveRelation, expr
    assert_instance_of Archsight::Query::AST::SubqueryTarget, expr.target
    inner = expr.target.query

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, inner.expression
  end

  def test_nested_subquery
    ast = parse("~> $(-> $(foo))")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingTransitiveRelation, expr
    assert_instance_of Archsight::Query::AST::SubqueryTarget, expr.target
    inner = expr.target.query

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, inner.expression
    inner_target = inner.expression.target

    assert_instance_of Archsight::Query::AST::SubqueryTarget, inner_target
  end

  def test_subquery_combined_with_annotation
    ast = parse('activity/status == "active" & -> $(kubernetes)')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.left
    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr.right
    assert_instance_of Archsight::Query::AST::SubqueryTarget, expr.right.target
  end

  # IN operator tests
  def test_in_condition_single_value
    ast = parse('repository/artifacts in ("container")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationInCondition, expr
    assert_equal "repository/artifacts", expr.path
    assert_equal 1, expr.values.length
    assert_instance_of Archsight::Query::AST::StringValue, expr.values[0]
    assert_equal "container", expr.values[0].value
  end

  def test_in_condition_multiple_values
    ast = parse('repository/artifacts in ("container", "chart")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationInCondition, expr
    assert_equal "repository/artifacts", expr.path
    assert_equal 2, expr.values.length
    assert_equal "container", expr.values[0].value
    assert_equal "chart", expr.values[1].value
  end

  def test_in_condition_three_values
    ast = parse('status in ("active", "maintenance", "deprecated")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationInCondition, expr
    assert_equal 3, expr.values.length
    assert_equal "active", expr.values[0].value
    assert_equal "maintenance", expr.values[1].value
    assert_equal "deprecated", expr.values[2].value
  end

  def test_in_condition_with_quoted_path
    ast = parse("'scc/language/C++/type' in (\"header\", \"source\")")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationInCondition, expr
    assert_equal "scc/language/C++/type", expr.path
    assert_equal 2, expr.values.length
  end

  def test_in_condition_combined_with_and
    ast = parse('activity/status == "active" & repository/artifacts in ("container", "chart")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.left
    assert_instance_of Archsight::Query::AST::AnnotationInCondition, expr.right
  end

  def test_in_condition_with_kind_filter
    ast = parse('TechnologyArtifact: repository/artifacts in ("container", "chart")')

    assert_equal "TechnologyArtifact", ast.kind_filter
    assert_instance_of Archsight::Query::AST::AnnotationInCondition, ast.expression
  end

  def test_in_condition_uppercase
    ast = parse('status IN ("active", "pending")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::AnnotationInCondition, expr
    assert_equal 2, expr.values.length
  end

  # Error cases
  def test_empty_query_error
    assert_raises(Archsight::Query::QueryError) { parse("") }
  end

  def test_incomplete_condition
    assert_raises(Archsight::Query::QueryError) { parse("foo ==") }
  end

  def test_missing_relation_target
    assert_raises(Archsight::Query::QueryError) { parse("->") }
  end

  def test_unclosed_parenthesis
    assert_raises(Archsight::Query::QueryError) { parse('(foo == "bar"') }
  end

  def test_empty_subquery_error
    assert_raises(Archsight::Query::QueryError) { parse("-> $()") }
  end

  def test_unclosed_subquery
    assert_raises(Archsight::Query::QueryError) { parse("-> $(foo") }
  end

  # Kind operator tests
  def test_kind_regex_match
    ast = parse('kind =~ "Technology.*"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::KindCondition, expr
    assert_equal "=~", expr.operator
    assert_equal "Technology.*", expr.value.value
  end

  def test_kind_in_condition_single
    ast = parse('kind in ("TechnologyArtifact")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::KindInCondition, expr
    assert_equal 1, expr.values.length
    assert_equal "TechnologyArtifact", expr.values[0].value
  end

  def test_kind_in_condition_multiple
    ast = parse('kind in ("TechnologyArtifact", "ApplicationComponent")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::KindInCondition, expr
    assert_equal 2, expr.values.length
    assert_equal "TechnologyArtifact", expr.values[0].value
    assert_equal "ApplicationComponent", expr.values[1].value
  end

  def test_kind_in_with_kind_filter
    ast = parse('TechnologyArtifact: kind in ("TechnologyArtifact", "ApplicationComponent")')

    assert_equal "TechnologyArtifact", ast.kind_filter
    assert_instance_of Archsight::Query::AST::KindInCondition, ast.expression
  end

  # Name IN operator tests
  def test_name_in_condition_single
    ast = parse('name in ("service-a")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NameInCondition, expr
    assert_equal 1, expr.values.length
    assert_equal "service-a", expr.values[0].value
  end

  def test_name_in_condition_multiple
    ast = parse('name in ("service-a", "service-b", "service-c")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::NameInCondition, expr
    assert_equal 3, expr.values.length
    assert_equal "service-a", expr.values[0].value
    assert_equal "service-b", expr.values[1].value
    assert_equal "service-c", expr.values[2].value
  end

  def test_name_in_combined_with_annotation
    ast = parse('name in ("a", "b") & activity/status == "active"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::NameInCondition, expr.left
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.right
  end

  def test_kind_regex_combined_with_annotation
    ast = parse('kind =~ "Application.*" & activity/status == "active"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::KindCondition, expr.left
    assert_equal "=~", expr.left.operator
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.right
  end

  # Verb filter tests
  def test_outgoing_direct_with_single_include_verb
    ast = parse("-{maintainedBy}> BusinessActor")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::KindTarget, expr.target
    assert_equal "BusinessActor", expr.target.kind_name
    assert_equal ["maintainedBy"], expr.verbs
    refute expr.exclude_verbs
  end

  def test_outgoing_direct_with_multiple_include_verbs
    ast = parse("-{maintainedBy,realizedThrough}> BusinessActor")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_equal %w[maintainedBy realizedThrough], expr.verbs
    refute expr.exclude_verbs
  end

  def test_outgoing_direct_with_single_exclude_verb
    ast = parse("-{!contributedBy}> BusinessActor")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_equal ["contributedBy"], expr.verbs
    assert expr.exclude_verbs
  end

  def test_outgoing_direct_with_multiple_exclude_verbs
    ast = parse("-{!contributedBy,servedBy}> BusinessActor")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_equal %w[contributedBy servedBy], expr.verbs
    assert expr.exclude_verbs
  end

  def test_outgoing_transitive_with_include_verb
    ast = parse("~{realizedThrough}> TechnologyArtifact")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingTransitiveRelation, expr
    assert_instance_of Archsight::Query::AST::KindTarget, expr.target
    assert_equal "TechnologyArtifact", expr.target.kind_name
    assert_equal ["realizedThrough"], expr.verbs
    refute expr.exclude_verbs
  end

  def test_outgoing_transitive_with_exclude_verb
    ast = parse("~{!contributedBy}> BusinessActor")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingTransitiveRelation, expr
    assert_equal ["contributedBy"], expr.verbs
    assert expr.exclude_verbs
  end

  def test_incoming_direct_with_include_verb
    ast = parse("<{maintainedBy}- TechnologyArtifact")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::IncomingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::KindTarget, expr.target
    assert_equal "TechnologyArtifact", expr.target.kind_name
    assert_equal ["maintainedBy"], expr.verbs
    refute expr.exclude_verbs
  end

  def test_incoming_direct_with_exclude_verb
    ast = parse("<{!contributedBy}- TechnologyArtifact")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::IncomingDirectRelation, expr
    assert_equal ["contributedBy"], expr.verbs
    assert expr.exclude_verbs
  end

  def test_incoming_transitive_with_include_verb
    ast = parse("<{realizedThrough}~ ApplicationComponent")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::IncomingTransitiveRelation, expr
    assert_instance_of Archsight::Query::AST::KindTarget, expr.target
    assert_equal "ApplicationComponent", expr.target.kind_name
    assert_equal ["realizedThrough"], expr.verbs
    refute expr.exclude_verbs
  end

  def test_incoming_transitive_with_exclude_verb
    ast = parse("<{!contributedBy}~ ApplicationComponent")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::IncomingTransitiveRelation, expr
    assert_equal ["contributedBy"], expr.verbs
    assert expr.exclude_verbs
  end

  def test_verb_filter_with_instance_target
    ast = parse('-{maintainedBy}> "ComputeTeam:Team"')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::InstanceTarget, expr.target
    assert_equal "ComputeTeam:Team", expr.target.instance_name
    assert_equal ["maintainedBy"], expr.verbs
  end

  def test_verb_filter_with_subquery_target
    ast = parse('-{maintainedBy}> $(activity/status == "active")')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::SubqueryTarget, expr.target
    assert_equal ["maintainedBy"], expr.verbs
    refute expr.exclude_verbs
  end

  def test_verb_filter_combined_with_kind_filter
    ast = parse("TechnologyArtifact: -{maintainedBy}> BusinessActor")

    assert_equal "TechnologyArtifact", ast.kind_filter
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_equal ["maintainedBy"], expr.verbs
  end

  def test_verb_filter_combined_with_and
    ast = parse('activity/status == "active" & -{maintainedBy}> BusinessActor')
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::BinaryOp, expr
    assert_equal :and, expr.operator
    assert_instance_of Archsight::Query::AST::AnnotationCondition, expr.left
    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr.right
    assert_equal ["maintainedBy"], expr.right.verbs
  end

  def test_standard_relation_has_nil_verbs
    ast = parse("-> ApplicationInterface")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_nil expr.verbs
    refute expr.exclude_verbs
  end

  def test_verb_filter_with_none_target
    ast = parse("-{maintainedBy}> none")
    expr = ast.expression

    assert_instance_of Archsight::Query::AST::OutgoingDirectRelation, expr
    assert_instance_of Archsight::Query::AST::NothingTarget, expr.target
    assert_equal ["maintainedBy"], expr.verbs
  end
end
