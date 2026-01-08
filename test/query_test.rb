# frozen_string_literal: true

require "test_helper"
require "archsight/query"

class QueryLexerTest < Minitest::Test
  def tokenize(input)
    lexer = Archsight::Query::Lexer.new(input)
    lexer.tokenize
  end

  def test_empty_input
    tokens = tokenize("")

    assert_equal 1, tokens.length
    assert_equal :EOF, tokens.first.type
  end

  def test_whitespace_only
    tokens = tokenize("   \t\n  ")

    assert_equal 1, tokens.length
  end

  def test_simple_identifier
    tokens = tokenize("name")

    assert_equal :NAME, tokens.first.type
  end

  def test_identifier_with_path
    tokens = tokenize("activity/status")

    assert_equal :IDENTIFIER, tokens.first.type
    assert_equal "activity/status", tokens.first.value
  end

  def test_double_quoted_string
    tokens = tokenize('"hello world"')

    assert_equal :STRING, tokens.first.type
    assert_equal "hello world", tokens.first.value
  end

  def test_single_quoted_string
    tokens = tokenize("'hello'")

    assert_equal :STRING, tokens.first.type
  end

  def test_escaped_string
    tokens = tokenize('"hello \"world\""')

    assert_equal :STRING, tokens.first.type
  end

  def test_number_integer
    tokens = tokenize("42")

    assert_equal :NUMBER, tokens.first.type
    assert_in_delta(42.0, tokens.first.value)
  end

  def test_number_decimal
    tokens = tokenize("3.14")

    assert_equal :NUMBER, tokens.first.type
    assert_in_delta(3.14, tokens.first.value)
  end

  def test_regex
    tokens = tokenize("/pattern/")

    assert_equal :REGEX, tokens.first.type
  end

  def test_regex_with_flags
    tokens = tokenize("/pattern/i")

    assert_equal :REGEX, tokens.first.type
    assert_equal "i", tokens.first.value[:flags]
  end

  def test_comparison_operators
    operators = { "==" => :EQ, "!=" => :NEQ, "=~" => :MATCH, ">=" => :GTE, "<=" => :LTE, ">" => :GT, "<" => :LT }
    operators.each do |op, type|
      tokens = tokenize(op)

      assert_equal type, tokens.first.type
    end
  end

  def test_logical_operators
    tokens = tokenize("& |")

    assert_equal :AND, tokens[0].type
    assert_equal :OR, tokens[1].type
  end

  def test_not_operator
    tokens = tokenize("!")

    assert_equal :NOT, tokens.first.type
  end

  def test_relation_operators
    operators = { "->" => :OUTGOING_DIRECT, "~>" => :OUTGOING_TRANSITIVE, "<-" => :INCOMING_DIRECT, "<~" => :INCOMING_TRANSITIVE }
    operators.each do |op, type|
      tokens = tokenize(op)

      assert_equal type, tokens.first.type
    end
  end

  def test_parentheses
    tokens = tokenize("()")

    assert_equal :LPAREN, tokens[0].type
    assert_equal :RPAREN, tokens[1].type
  end

  def test_braces
    tokens = tokenize("{}")

    assert_equal :LBRACE, tokens[0].type
    assert_equal :RBRACE, tokens[1].type
  end

  def test_colon
    tokens = tokenize(":")

    assert_equal :COLON, tokens.first.type
  end

  def test_dollar
    tokens = tokenize("$")

    assert_equal :DOLLAR, tokens.first.type
  end

  def test_comma
    tokens = tokenize(",")

    assert_equal :COMMA, tokens.first.type
  end

  def test_question
    tokens = tokenize("?")

    assert_equal :QUESTION, tokens.first.type
  end

  def test_keywords
    keywords = { "and" => :AND, "or" => :OR, "not" => :NOT, "kind" => :KIND, "name" => :NAME, "none" => :NONE, "in" => :IN }
    keywords.each do |kw, type|
      tokens = tokenize(kw)

      assert_equal type, tokens.first.type
    end
  end

  def test_keywords_case_insensitive
    tokens = tokenize("AND Or NOT")

    assert_equal :AND, tokens[0].type
    assert_equal :OR, tokens[1].type
    assert_equal :NOT, tokens[2].type
  end

  def test_full_query
    tokens = tokenize('name == "test" AND status == "active"')
    types = tokens.map(&:type)

    assert_includes types, :NAME
    assert_includes types, :EQ
    assert_includes types, :STRING
    assert_includes types, :AND
  end

  def test_unterminated_string
    assert_raises(Archsight::Query::LexerError) { tokenize('"unterminated') }
  end

  def test_unterminated_single_quoted_string
    assert_raises(Archsight::Query::LexerError) { tokenize("'unterminated") }
  end

  def test_unterminated_regex
    assert_raises(Archsight::Query::LexerError) { tokenize("/unterminated") }
  end

  def test_unexpected_character
    assert_raises(Archsight::Query::LexerError) { tokenize("@") }
  end

  def test_token_position
    tokens = tokenize("a b")

    assert_equal 0, tokens[0].position
    assert_equal 2, tokens[1].position
  end

  def test_token_to_s
    tokens = tokenize("test")

    assert_includes tokens.first.to_s, "IDENTIFIER"
  end

  def test_dash_before_brace
    tokens = tokenize("-{")

    assert_equal :DASH, tokens[0].type
    assert_equal :LBRACE, tokens[1].type
  end

  def test_tilde_before_brace
    tokens = tokenize("~{")

    assert_equal :TILDE, tokens[0].type
  end

  def test_lt_before_brace
    tokens = tokenize("<{")

    assert_equal :LT, tokens[0].type
  end

  def test_standalone_dash
    tokens = tokenize("-")

    assert_equal :DASH, tokens[0].type
  end

  def test_standalone_tilde
    tokens = tokenize("~")

    assert_equal :TILDE, tokens[0].type
  end
end

class QueryParserTest < Minitest::Test
  def parse(input)
    Archsight::Query::Query.new(input)
  end

  def test_simple_name_query
    query = parse('name == "test"')

    refute_nil query.ast
  end

  def test_name_shortcut
    query = parse("test")

    refute_nil query.ast
  end

  def test_regex_match
    query = parse('name =~ ".*test.*"')

    refute_nil query.ast
  end

  def test_kind_filter
    query = parse('TechnologyArtifact: name == "test"')

    assert_equal "TechnologyArtifact", query.kind_filter
  end

  def test_and_expression
    query = parse('name == "a" AND name == "b"')

    refute_nil query.ast
  end

  def test_or_expression
    query = parse('name == "a" OR name == "b"')

    refute_nil query.ast
  end

  def test_not_expression
    query = parse('NOT name == "test"')

    refute_nil query.ast
  end

  def test_complex_logical
    query = parse('(name == "a" OR name == "b") AND status == "active"')

    refute_nil query.ast
  end

  def test_numeric_comparison
    query = parse("loc > 1000")

    refute_nil query.ast
  end

  def test_all_comparisons
    %w[== != =~ > < >= <=].each do |op|
      query = parse("value #{op} 100")

      refute_nil query.ast
    end
  end

  def test_outgoing_relation
    query = parse("-> TechnologyArtifact")

    refute_nil query.ast
  end

  def test_incoming_relation
    query = parse("<- ApplicationComponent")

    refute_nil query.ast
  end

  def test_transitive_outgoing
    query = parse("~> TechnologyArtifact")

    refute_nil query.ast
  end

  def test_transitive_incoming
    query = parse("<~ ApplicationComponent")

    refute_nil query.ast
  end

  def test_relation_to_named
    query = parse('-> "specific-name"')

    refute_nil query.ast
  end

  def test_relation_none
    query = parse("-> none")

    refute_nil query.ast
  end

  def test_subquery
    query = parse('-> $(name == "test")')

    refute_nil query.ast
  end

  def test_to_s
    query = parse('name == "test"')

    assert_includes query.to_s, "Query"
  end

  def test_inspect
    query = parse('name == "test"')

    assert_includes query.inspect, "Query"
  end

  def test_invalid_syntax
    assert_raises(Archsight::Query::QueryError) { parse("((invalid") }
  end
end

class QueryEvaluatorTest < Minitest::Test
  def setup
    @resources_dir = File.expand_path("../examples/archsight", __dir__)
    @db = Archsight::Database.new(@resources_dir, verbose: false)
    @db.reload!
  end

  def query(input)
    Archsight::Query::Query.new(input)
  end

  def filter(input)
    query(input).filter(@db)
  end

  def test_filter_all_by_regex
    results = filter('name =~ ".*"')

    refute_empty results
  end

  def test_filter_by_exact_name
    artifacts = @db.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?
    name = artifacts.keys.first
    results = filter("name == \"#{name}\"")

    assert_equal 1, results.length
  end

  def test_filter_by_kind
    results = filter('TechnologyArtifact: name =~ ".*"')

    refute_empty results
    results.each { |r| assert_equal "TechnologyArtifact", r.kind }
  end

  def test_filter_with_and
    results = filter('name =~ ".*" AND kind == "TechnologyArtifact"')

    results.each { |r| assert_equal "TechnologyArtifact", r.kind }
  end

  def test_filter_with_or
    results = filter('kind == "TechnologyArtifact" OR kind == "ApplicationComponent"')

    results.each { |r| assert_includes %w[TechnologyArtifact ApplicationComponent], r.kind }
  end

  def test_filter_with_not
    all_results = filter('name =~ ".*"')
    artifacts = filter('TechnologyArtifact: name =~ ".*"')
    not_artifacts = filter('NOT kind == "TechnologyArtifact"')

    assert_equal all_results.length, not_artifacts.length + artifacts.length
  end

  def test_matches_true
    artifacts = @db.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?
    instance = artifacts.values.first
    q = query('name =~ ".*"')

    assert q.matches?(instance, database: @db)
  end

  def test_matches_false
    artifacts = @db.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?
    instance = artifacts.values.first
    q = query('name == "nonexistent-name-xyz"')

    refute q.matches?(instance, database: @db)
  end

  def test_filter_by_annotation
    results = filter('activity/status == "active"')

    assert_kind_of Array, results
  end

  def test_filter_by_numeric_annotation
    results = filter("scc/total_loc > 0")

    assert_kind_of Array, results
  end

  def test_filter_outgoing_relation
    results = filter("-> TechnologyArtifact")

    assert_kind_of Array, results
  end

  def test_filter_incoming_relation
    results = filter("<- ApplicationComponent")

    assert_kind_of Array, results
  end

  def test_filter_relation_none
    results = filter("-> none")

    assert_kind_of Array, results
  end

  def test_filter_incoming_none
    results = filter("<- none")

    assert_kind_of Array, results
  end

  def test_shortcut_name_search
    artifacts = @db.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?
    name = artifacts.keys.first
    partial = name[0..3] if name.length > 3
    results = filter(partial.to_s)

    assert_kind_of Array, results
  end

  def test_not_equal
    results = filter('NOT kind == "TechnologyArtifact"')

    results.each { |r| refute_equal "TechnologyArtifact", r.kind }
  end

  def test_greater_than_or_equal
    results = filter("scc/total_loc >= 0")

    assert_kind_of Array, results
  end

  def test_less_than_or_equal
    results = filter("scc/total_loc <= 999999")

    assert_kind_of Array, results
  end

  def test_less_than
    results = filter("scc/total_loc < 999999")

    assert_kind_of Array, results
  end

  def test_transitive_outgoing_relation
    results = filter("~> TechnologyArtifact")

    assert_kind_of Array, results
  end

  def test_transitive_incoming_relation
    results = filter("<~ ApplicationComponent")

    assert_kind_of Array, results
  end
end

class QueryErrorsTest < Minitest::Test
  def test_lexer_error
    error = Archsight::Query::LexerError.new("test", position: 5, source: "abc")

    assert_includes error.message, "test"
    assert_equal 5, error.position
  end

  def test_parse_error
    error = Archsight::Query::ParseError.new("test", position: 10)

    assert_includes error.message, "test"
    assert_equal 10, error.position
  end

  def test_query_error
    error = Archsight::Query::QueryError.new("test", position: 3, source: "query")

    assert_includes error.message, "test"
    assert_equal 3, error.position
    assert_equal "query", error.source
  end

  def test_evaluation_error
    error = Archsight::Query::EvaluationError.new("test")

    assert_includes error.message, "test"
  end
end

class QueryConvenienceTest < Minitest::Test
  def test_parse_convenience_method
    query = Archsight::Query.parse('name == "test"')

    refute_nil query
    assert_kind_of Archsight::Query::Query, query
  end
end

class QueryASTTest < Minitest::Test
  def test_query_node
    node = Archsight::Query::AST::QueryNode.new("TechnologyArtifact", nil)

    assert_equal "TechnologyArtifact", node.kind_filter
  end

  def test_binary_op
    node = Archsight::Query::AST::BinaryOp.new(:and, nil, nil)

    assert_equal :and, node.operator
  end

  def test_not_op
    node = Archsight::Query::AST::NotOp.new(nil)

    assert_nil node.operand
  end

  def test_annotation_condition
    node = Archsight::Query::AST::AnnotationCondition.new("activity/status", "==", nil)

    assert_equal "activity/status", node.path
    assert_equal "==", node.operator
  end

  def test_annotation_exists_condition
    node = Archsight::Query::AST::AnnotationExistsCondition.new("activity/status")

    assert_equal "activity/status", node.path
  end

  def test_string_value
    node = Archsight::Query::AST::StringValue.new("test")

    assert_equal "test", node.value
  end

  def test_number_value
    node = Archsight::Query::AST::NumberValue.new(42)

    assert_equal 42, node.value
  end
end
