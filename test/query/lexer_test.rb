# frozen_string_literal: true

require_relative "../test_helper"

class LexerTest < Minitest::Test
  def tokenize(source)
    Archsight::Query::Lexer.new(source).tokenize
  end

  def token_types(source)
    tokenize(source).map(&:type)
  end

  def token_values(source)
    tokenize(source).map(&:value)
  end

  # Basic token tests
  def test_empty_string
    assert_equal [:EOF], token_types("")
  end

  def test_whitespace_only
    assert_equal [:EOF], token_types("   ")
  end

  def test_identifier
    tokens = tokenize("foo")

    assert_equal %i[IDENTIFIER EOF], token_types("foo")
    assert_equal "foo", tokens[0].value
  end

  def test_identifier_with_slashes
    tokens = tokenize("activity/status")

    assert_equal %i[IDENTIFIER EOF], token_types("activity/status")
    assert_equal "activity/status", tokens[0].value
  end

  def test_nested_path
    tokens = tokenize("scc/language/Go/loc")

    assert_equal %i[IDENTIFIER EOF], token_types("scc/language/Go/loc")
    assert_equal "scc/language/Go/loc", tokens[0].value
  end

  def test_identifier_with_dots
    tokens = tokenize("teleport.e")

    assert_equal %i[IDENTIFIER EOF], token_types("teleport.e")
    assert_equal "teleport.e", tokens[0].value
  end

  # String tests
  def test_double_quoted_string
    tokens = tokenize('"active"')

    assert_equal %i[STRING EOF], token_types('"active"')
    assert_equal "active", tokens[0].value
  end

  def test_string_with_spaces
    tokens = tokenize('"hello world"')

    assert_equal "hello world", tokens[0].value
  end

  def test_string_with_colon
    tokens = tokenize('"Kubernetes:RestAPI"')

    assert_equal "Kubernetes:RestAPI", tokens[0].value
  end

  # Single-quoted string tests
  def test_single_quoted_string
    tokens = tokenize("'active'")

    assert_equal %i[STRING EOF], token_types("'active'")
    assert_equal "active", tokens[0].value
  end

  def test_single_quoted_string_with_plus
    tokens = tokenize("'scc/language/C++/loc'")

    assert_equal %i[STRING EOF], token_types("'scc/language/C++/loc'")
    assert_equal "scc/language/C++/loc", tokens[0].value
  end

  def test_single_quoted_in_comparison
    types = token_types("'scc/language/C++/loc' >= 500")

    assert_equal %i[STRING GTE NUMBER EOF], types
  end

  def test_unterminated_single_quoted_string
    assert_raises(Archsight::Query::LexerError) { tokenize("'unterminated") }
  end

  # Number tests
  def test_integer
    tokens = tokenize("42")

    assert_equal %i[NUMBER EOF], token_types("42")
    assert_in_delta(42.0, tokens[0].value)
  end

  def test_float
    tokens = tokenize("3.14")

    assert_equal %i[NUMBER EOF], token_types("3.14")
    assert_in_delta(3.14, tokens[0].value)
  end

  # Comparison operator tests
  def test_equals
    assert_equal %i[IDENTIFIER EQ STRING EOF], token_types('foo == "bar"')
  end

  def test_not_equals
    assert_equal %i[IDENTIFIER NEQ STRING EOF], token_types('foo != "bar"')
  end

  def test_regex_match
    assert_equal %i[IDENTIFIER MATCH STRING EOF], token_types('foo =~ "bar"')
  end

  def test_greater_than
    assert_equal %i[IDENTIFIER GT NUMBER EOF], token_types("foo > 5")
  end

  def test_less_than
    assert_equal %i[IDENTIFIER LT NUMBER EOF], token_types("foo < 5")
  end

  def test_greater_or_equal
    assert_equal %i[IDENTIFIER GTE NUMBER EOF], token_types("foo >= 5")
  end

  def test_less_or_equal
    assert_equal %i[IDENTIFIER LTE NUMBER EOF], token_types("foo <= 5")
  end

  # Logical operator tests
  def test_and_uppercase
    assert_equal %i[IDENTIFIER AND IDENTIFIER EOF], token_types("foo AND bar")
  end

  def test_and_lowercase
    assert_equal %i[IDENTIFIER AND IDENTIFIER EOF], token_types("foo and bar")
  end

  def test_and_ampersand
    assert_equal %i[IDENTIFIER AND IDENTIFIER EOF], token_types("foo & bar")
  end

  def test_or_uppercase
    assert_equal %i[IDENTIFIER OR IDENTIFIER EOF], token_types("foo OR bar")
  end

  def test_or_lowercase
    assert_equal %i[IDENTIFIER OR IDENTIFIER EOF], token_types("foo or bar")
  end

  def test_or_pipe
    assert_equal %i[IDENTIFIER OR IDENTIFIER EOF], token_types("foo | bar")
  end

  def test_not_uppercase
    assert_equal %i[NOT IDENTIFIER EOF], token_types("NOT foo")
  end

  def test_not_lowercase
    assert_equal %i[NOT IDENTIFIER EOF], token_types("not foo")
  end

  def test_not_bang
    assert_equal %i[NOT IDENTIFIER EOF], token_types("! foo")
  end

  # Relation operator tests
  def test_outgoing_direct
    assert_equal %i[OUTGOING_DIRECT IDENTIFIER EOF], token_types("-> Foo")
  end

  def test_outgoing_transitive
    assert_equal %i[OUTGOING_TRANSITIVE IDENTIFIER EOF], token_types("~> Foo")
  end

  def test_incoming_direct
    assert_equal %i[INCOMING_DIRECT IDENTIFIER EOF], token_types("<- Foo")
  end

  def test_incoming_transitive
    assert_equal %i[INCOMING_TRANSITIVE IDENTIFIER EOF], token_types("<~ Foo")
  end

  # Kind filter tests
  def test_kind_filter
    types = token_types("TechnologyArtifact: foo")

    assert_equal %i[IDENTIFIER COLON IDENTIFIER EOF], types
  end

  def test_kind_keyword
    assert_equal %i[KIND EQ STRING EOF], token_types('kind == "Foo"')
  end

  def test_name_keyword
    assert_equal %i[NAME EQ STRING EOF], token_types('name == "Foo"')
  end

  def test_name_keyword_regex
    assert_equal %i[NAME MATCH STRING EOF], token_types('name =~ "foo.*"')
  end

  # Parentheses tests
  def test_parentheses
    types = token_types("(foo)")

    assert_equal %i[LPAREN IDENTIFIER RPAREN EOF], types
  end

  # Complex query tests
  def test_annotation_query
    types = token_types('activity/status == "active"')

    assert_equal %i[IDENTIFIER EQ STRING EOF], types
  end

  def test_combined_query_with_and
    types = token_types('activity/status == "active" & repository/artifacts == "container"')

    assert_equal %i[IDENTIFIER EQ STRING AND IDENTIFIER EQ STRING EOF], types
  end

  def test_relation_query
    types = token_types("-> ApplicationInterface")

    assert_equal %i[OUTGOING_DIRECT IDENTIFIER EOF], types
  end

  def test_full_query_with_kind_filter
    types = token_types('TechnologyArtifact: activity/status == "active" & repository/artifacts == "container"')

    assert_equal %i[IDENTIFIER COLON IDENTIFIER EQ STRING AND IDENTIFIER EQ STRING EOF], types
  end

  # Question mark (existence check) tests
  def test_question_mark_token
    assert_equal %i[QUESTION EOF], token_types("?")
  end

  def test_identifier_with_question_mark
    types = token_types("activity/status?")

    assert_equal %i[IDENTIFIER QUESTION EOF], types
  end

  # Subquery tests
  def test_dollar_token
    assert_equal %i[DOLLAR EOF], token_types("$")
  end

  def test_dollar_with_parens
    types = token_types("$(foo)")

    assert_equal %i[DOLLAR LPAREN IDENTIFIER RPAREN EOF], types
  end

  def test_subquery_with_relation
    types = token_types("-> $(kubernetes)")

    assert_equal %i[OUTGOING_DIRECT DOLLAR LPAREN IDENTIFIER RPAREN EOF], types
  end

  def test_subquery_with_kind_filter
    types = token_types("$(TechnologyArtifact: active)")

    assert_equal %i[DOLLAR LPAREN IDENTIFIER COLON IDENTIFIER RPAREN EOF], types
  end

  # IN operator tests
  def test_in_keyword_lowercase
    assert_equal %i[IDENTIFIER IN LPAREN STRING RPAREN EOF], token_types('foo in ("bar")')
  end

  def test_in_keyword_uppercase
    assert_equal %i[IDENTIFIER IN LPAREN STRING RPAREN EOF], token_types('foo IN ("bar")')
  end

  def test_comma_token
    assert_equal %i[COMMA EOF], token_types(",")
  end

  def test_in_with_multiple_values
    types = token_types('repository/artifacts in ("container", "chart")')

    assert_equal %i[IDENTIFIER IN LPAREN STRING COMMA STRING RPAREN EOF], types
  end

  # Error cases
  def test_unterminated_string
    assert_raises(Archsight::Query::LexerError) { tokenize('"unterminated') }
  end

  def test_invalid_character
    assert_raises(Archsight::Query::LexerError) { tokenize("@invalid") }
  end
end
