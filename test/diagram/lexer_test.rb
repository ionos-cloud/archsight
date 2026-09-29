# frozen_string_literal: true

require_relative "../test_helper"

class DiagramLexerTest < Minitest::Test
  def test_tokenizes_a_simple_block
    tokens = Archsight::Diagram::Lexer.new(%(node "a" { label "A" }\n)).tokenize

    assert_equal %i[ident string lbrace ident string rbrace eof], tokens.map(&:type)
    assert_equal ["node", "a", "{", "label", "A", "}", nil], tokens.map(&:value)
  end

  def test_tokenizes_an_edge_with_an_arrow
    assert_equal %i[ident arrow ident eof], types("a -> b\n")
  end

  def test_tokenizes_a_bidirectional_edge
    tokens = Archsight::Diagram::Lexer.new("a <-> b\n").tokenize

    assert_equal %i[ident biarrow ident eof], tokens.map(&:type)
    assert_equal "<->", tokens[1].value
  end

  def test_tokenizes_an_undirected_edge
    tokens = Archsight::Diagram::Lexer.new("a -- b\n").tokenize

    assert_equal %i[ident undirected ident eof], tokens.map(&:type)
    assert_equal "--", tokens[1].value
  end

  def test_raises_on_a_lone_less_than
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Lexer.new("a < b").tokenize }
    assert_match(/did you mean/, error.message)
  end

  def test_tokenizes_an_edge_with_attributes_and_a_semicolon
    tokens = Archsight::Diagram::Lexer.new(%(a -> b { style "orthogonal"; }\n)).tokenize

    assert_equal %i[ident arrow ident lbrace ident string semi rbrace eof], tokens.map(&:type)
  end

  def test_skips_comments_and_blank_lines
    source = <<~SRC
      # a comment
      node "a" { }

      # another
    SRC

    assert_equal %i[ident string lbrace rbrace eof], types(source)
  end

  def test_tracks_line_numbers_across_newlines
    tokens = Archsight::Diagram::Lexer.new("node \"a\" {\n}\n").tokenize
    rbrace = tokens.find { |t| t.type == :rbrace }

    assert_equal 2, rbrace.line
  end

  def test_counts_an_escaped_newline_inside_a_string_as_a_line
    tokens = Archsight::Diagram::Lexer.new(%(label "a\\\nb"\n}\n)).tokenize
    rbrace = tokens.find { |t| t.type == :rbrace }

    assert_equal 3, rbrace.line
  end

  def test_raises_on_an_unterminated_string
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Lexer.new(%(node "a)).tokenize }
    assert_match(/unterminated string/, error.message)
  end

  def test_raises_on_a_lone_dash
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Lexer.new("a - b").tokenize }
    assert_match(/did you mean/, error.message)
  end

  def test_still_handles_an_escaped_quote_exactly_as_before
    tokens = Archsight::Diagram::Lexer.new(%(label "a \\"quoted\\" word"\n)).tokenize

    assert_equal 'a "quoted" word', tokens[1].value
  end

  def test_turns_a_n_escape_into_a_real_newline_preserving_a_deliberately_typed_leading_space_after_it
    # The trailing space before the closing quote is still trimmed (the
    # final line's trailing whitespace goes regardless of which form
    # produced the newline), but the leading space right after \n --
    # not source indentation, since \n sits on one physical line -- is
    # kept exactly as typed.
    tokens = Archsight::Diagram::Lexer.new(%(label "line one\\n line two "\n)).tokenize

    assert_equal "line one\n line two", tokens[1].value
  end

  def test_leaves_a_plain_single_line_string_byte_for_byte_unchanged
    tokens = Archsight::Diagram::Lexer.new(%(label "  padded on purpose  "\n)).tokenize

    assert_equal "  padded on purpose  ", tokens[1].value
  end

  def test_trims_each_line_s_leading_trailing_whitespace_in_a_raw_multi_line_string
    source = <<~SRC
      label "First line
             Second line
             Third line"
    SRC
    tokens = Archsight::Diagram::Lexer.new(source).tokenize

    assert_equal "First line\nSecond line\nThird line", tokens[1].value
  end

  def test_tracks_line_numbers_across_a_raw_multi_line_string
    source = <<~SRC
      label "First
             Second"
      component "x" { }
    SRC
    tokens = Archsight::Diagram::Lexer.new(source).tokenize
    component_token = tokens.find { |t| t.value == "component" }

    assert_equal 3, component_token.line
  end

  def test_handles_non_ascii_labels_and_keeps_line_numbers
    source = %(component "a" { label "Größe — ok" }\na -> b\n)
    tokens = Archsight::Diagram::Lexer.new(source).tokenize

    assert_equal "Größe — ok", tokens[4].value
    assert_equal [:ident, "a", 2], tokens[6].to_a
    assert_equal :arrow, tokens[7].type
  end

  def test_reports_a_non_ascii_unexpected_character_whole
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Lexer.new("a —").tokenize }
    assert_equal 'unexpected character "—" at line 1', error.message
  end

  def test_an_arrow_without_surrounding_spaces_is_not_split_out_of_an_identifier
    # `-` is an identifier char, so `a->b` lexes `a-` and then trips on `>`.
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Lexer.new("a->b").tokenize }
    assert_equal 'unexpected character ">" at line 1', error.message
  end

  def test_raises_on_a_string_ending_in_a_lone_backslash
    error = assert_raises(Archsight::Diagram::ParseError) { Archsight::Diagram::Lexer.new(%(label "a\\)).tokenize }
    assert_match(/unterminated string starting at line 1/, error.message)
  end

  private

  def types(source)
    Archsight::Diagram::Lexer.new(source).tokenize.map(&:type)
  end
end
