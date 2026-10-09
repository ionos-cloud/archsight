# frozen_string_literal: true

require_relative "errors"
require_relative "ast"

# Recursive descent parser for the architecture query language.
class Archsight::Query::Parser
  # Characters a resource name is made of, as the lexer reads an identifier
  NAME_CHAR = %r{[a-zA-Z0-9_\-/.]}

  # @param source [String, nil] the query text; with it, names that contain colons (`Archsight:CLI`, `ITGS:A001`)
  #   are read as one name instead of a kind prefix and a condition
  def initialize(tokens, source: nil)
    @tokens = tokens
    @source = source
    @position = 0
  end

  def parse
    # Check for kind filter prefix: "Kind: expression"
    kind_filter = nil
    if kind_prefix?
      kind_filter = current_token.value
      advance # consume identifier
      advance # consume colon
    end

    # Expression is optional when kind filter is present
    # "TechnologyArtifact:" is valid and returns all resources of that kind
    expression = if current_token.type == :EOF
                   nil
                 else
                   parse_or_expression
                 end

    # Empty query (no kind filter and no expression) is an error
    if kind_filter.nil? && expression.nil?
      raise Archsight::Query::ParseError.new(
        "Empty query: expected kind filter or expression",
        position: 0,
        source: nil
      )
    end

    expect(:EOF)

    Archsight::Query::AST::QueryNode.new(kind_filter, expression)
  end

  private

  def parse_or_expression
    left = parse_and_expression

    while current_token.type == :OR
      advance
      right = parse_and_expression
      left = Archsight::Query::AST::BinaryOp.new(:or, left, right)
    end

    left
  end

  def parse_and_expression
    left = parse_unary_expression

    while current_token.type == :AND
      advance
      right = parse_unary_expression
      left = Archsight::Query::AST::BinaryOp.new(:and, left, right)
    end

    left
  end

  def parse_unary_expression
    if current_token.type == :NOT
      advance
      operand = parse_primary
      Archsight::Query::AST::NotOp.new(operand)
    else
      parse_primary
    end
  end

  def parse_primary
    case current_token.type
    when :LPAREN
      advance
      expr = parse_or_expression
      expect(:RPAREN)
      expr
    when :OUTGOING_DIRECT
      parse_outgoing_direct_relation
    when :OUTGOING_TRANSITIVE
      parse_outgoing_transitive_relation
    when :INCOMING_DIRECT
      parse_incoming_direct_relation
    when :INCOMING_TRANSITIVE
      parse_incoming_transitive_relation
    when :DASH
      # -{...}> verb-filtered outgoing direct relation
      parse_outgoing_direct_relation_with_verbs
    when :TILDE
      # ~{...}> verb-filtered outgoing transitive relation
      parse_outgoing_transitive_relation_with_verbs
    when :LT
      # <{...}- or <{...}~ verb-filtered incoming relation
      # Note: :LT is emitted when lexer sees <{ (verb filter start)
      parse_incoming_relation_with_verbs
    when :KIND
      parse_kind_condition
    when :NAME
      parse_name_condition
    when :IDENTIFIER
      parse_identifier_or_shortcut
    when :STRING
      # Quoted annotation path: 'scc/language/C++/loc' >= 500
      parse_quoted_annotation_path
    else
      raise Archsight::Query::ParseError.new(
        "Unexpected token #{current_token.type}",
        position: current_token.position,
        source: nil
      )
    end
  end

  def parse_outgoing_direct_relation
    advance # consume ->
    target = parse_relation_target
    Archsight::Query::AST::OutgoingDirectRelation.new(target)
  end

  def parse_outgoing_transitive_relation
    advance # consume ~>
    target = parse_relation_target
    Archsight::Query::AST::OutgoingTransitiveRelation.new(target)
  end

  def parse_incoming_direct_relation
    advance # consume <-
    target = parse_relation_target
    Archsight::Query::AST::IncomingDirectRelation.new(target)
  end

  def parse_incoming_transitive_relation
    advance # consume <~
    target = parse_relation_target
    Archsight::Query::AST::IncomingTransitiveRelation.new(target)
  end

  # Parse verb filter: {verb1,verb2,...} or {!verb1,verb2,...}
  # Returns [verbs_array, exclude_flag]
  def parse_verb_filter
    expect(:LBRACE)

    exclude_verbs = false
    verbs = []

    # Check for ! prefix (exclude mode)
    if current_token.type == :NOT
      exclude_verbs = true
      advance
    end

    # Parse first verb (required)
    unless current_token.type == :IDENTIFIER
      raise Archsight::Query::ParseError.new(
        "Expected verb name in verb filter",
        position: current_token.position,
        source: nil
      )
    end
    verbs << current_token.value
    advance

    # Parse additional verbs (comma-separated)
    while current_token.type == :COMMA
      advance # consume comma
      unless current_token.type == :IDENTIFIER
        raise Archsight::Query::ParseError.new(
          "Expected verb name after comma in verb filter",
          position: current_token.position,
          source: nil
        )
      end
      verbs << current_token.value
      advance
    end

    expect(:RBRACE)
    [verbs, exclude_verbs]
  end

  def parse_outgoing_direct_relation_with_verbs
    advance # consume -
    verbs, exclude_verbs = parse_verb_filter
    expect(:GT) # consume >
    target = parse_relation_target
    Archsight::Query::AST::OutgoingDirectRelation.new(target, verbs, exclude_verbs)
  end

  def parse_outgoing_transitive_relation_with_verbs
    advance # consume ~
    verbs, exclude_verbs = parse_verb_filter
    expect(:GT) # consume >
    target = parse_relation_target
    Archsight::Query::AST::OutgoingTransitiveRelation.new(target, verbs, exclude_verbs)
  end

  def parse_incoming_relation_with_verbs
    advance # consume <
    verbs, exclude_verbs = parse_verb_filter

    # Determine if direct (<{...}-) or transitive (<{...}~) based on next token
    if current_token.type == :DASH
      advance # consume -
      target = parse_relation_target
      Archsight::Query::AST::IncomingDirectRelation.new(target, verbs, exclude_verbs)
    elsif current_token.type == :TILDE
      advance # consume ~
      target = parse_relation_target
      Archsight::Query::AST::IncomingTransitiveRelation.new(target, verbs, exclude_verbs)
    else
      raise Archsight::Query::ParseError.new(
        "Expected - or ~ after verb filter in incoming relation",
        position: current_token.position,
        source: nil
      )
    end
  end

  def parse_relation_target
    case current_token.type
    when :STRING
      name = current_token.value
      advance
      Archsight::Query::AST::InstanceTarget.new(name)
    when :IDENTIFIER
      kind = current_token.value
      advance
      Archsight::Query::AST::KindTarget.new(kind)
    when :NONE
      advance
      Archsight::Query::AST::NothingTarget.new
    when :DOLLAR
      parse_subquery_target
    else
      raise Archsight::Query::ParseError.new(
        "Expected kind, instance name, none, or $(subquery)",
        position: current_token.position,
        source: nil
      )
    end
  end

  def parse_subquery_target
    advance # consume $
    expect(:LPAREN)

    # Parse inner query: optional kind filter + optional expression
    kind_filter = nil
    if kind_prefix?
      kind_filter = current_token.value
      advance # consume identifier
      advance # consume colon
    end

    # Expression is optional when kind filter is present
    expression = if current_token.type == :RPAREN
                   nil
                 else
                   parse_or_expression
                 end

    # Subquery must have either kind filter or expression
    if kind_filter.nil? && expression.nil?
      raise Archsight::Query::ParseError.new(
        "Empty subquery: expected kind filter or expression inside $()",
        position: current_token.position,
        source: nil
      )
    end

    expect(:RPAREN)

    inner_query = Archsight::Query::AST::QueryNode.new(kind_filter, expression)
    Archsight::Query::AST::SubqueryTarget.new(inner_query)
  end

  def parse_kind_condition
    advance # consume 'kind'

    # Parse operator
    op_token = current_token
    unless %i[EQ MATCH IN].include?(op_token.type)
      raise Archsight::Query::ParseError.new(
        "Expected ==, =~, or 'in' after 'kind'",
        position: op_token.position,
        source: nil
      )
    end

    if op_token.type == :IN
      advance
      return parse_kind_in_condition
    end

    operator = op_token.type == :EQ ? "==" : "=~"
    advance

    # Parse value
    value_token = current_token
    value = parse_value
    check_value(operator, value, value_token)

    Archsight::Query::AST::KindCondition.new(operator, value)
  end

  def parse_kind_in_condition
    expect(:LPAREN)

    values = []
    values << parse_in_value

    while current_token.type == :COMMA
      advance # consume comma
      values << parse_in_value
    end

    expect(:RPAREN)

    Archsight::Query::AST::KindInCondition.new(values)
  end

  def parse_name_condition
    advance # consume 'name'

    # Parse operator
    op_token = current_token
    unless %i[EQ NEQ MATCH IN].include?(op_token.type)
      raise Archsight::Query::ParseError.new(
        "Expected ==, !=, =~, or 'in' after 'name'",
        position: op_token.position,
        source: nil
      )
    end

    if op_token.type == :IN
      advance
      return parse_name_in_condition
    end

    advance

    # Parse value
    value_token = current_token
    value = parse_value

    operator = case op_token.type
               when :EQ then "=="
               when :NEQ then "!="
               when :MATCH then "=~"
               end
    check_value(operator, value, value_token)

    Archsight::Query::AST::NameCondition.new(operator, value)
  end

  def parse_name_in_condition
    expect(:LPAREN)

    values = []
    values << parse_in_value

    while current_token.type == :COMMA
      advance # consume comma
      values << parse_in_value
    end

    expect(:RPAREN)

    Archsight::Query::AST::NameInCondition.new(values)
  end

  def parse_identifier_or_shortcut
    path = current_token.value
    advance

    # Check if this is followed by an operator (annotation condition),
    # a question mark (existence check), or a bare identifier (name shortcut)
    if %i[EQ NEQ MATCH GT LT GTE LTE IN].include?(current_token.type)
      # This is an annotation condition with comparison operator
      parse_annotation_condition_with_path(path)
    elsif current_token.type == :QUESTION
      # Existence check: path?
      advance # consume ?
      Archsight::Query::AST::AnnotationExistsCondition.new(path)
    else
      # Bare identifier - treat as name =~ "identifier"
      Archsight::Query::AST::NameCondition.new("=~", Archsight::Query::AST::StringValue.new(glue_name(path)))
    end
  end

  # Names contain colons (`Archsight:CLI`, `ITGS:A001`). A bare name written without spaces around its colons is
  # one word: `ApplicationService:ITGS:A001` is the kind and the name `ITGS:A001`.
  def glue_name(first)
    name = first
    while (word = word_after_colon)
      name += ":#{word}"
      advance # consume the colon
      advance while current_token.type != :EOF && current_token.position < @colon_end
    end
    name
  end

  # The name word right after the current colon token, when the colon touches a name character on both sides
  def word_after_colon
    return nil unless @source && current_token.type == :COLON

    colon = current_token.position
    return nil unless colon.positive? && @source[colon - 1]&.match?(NAME_CHAR)

    word = @source[(colon + 1)..].to_s[/\A#{NAME_CHAR}+/]
    @colon_end = colon + 1 + word.length if word
    word
  end

  # `Kind: expression` or `Kind:`. The prefix is a kind when it starts with a capital letter and the colon is followed
  # by a space or nothing; `Name:Word` without a space, where the prefix is no kind, is a name with a colon
  # (`ITGS:A001`) that the bare word search handles.
  def kind_prefix?
    return false unless current_token.type == :IDENTIFIER && peek_token&.type == :COLON && current_token.value =~ /^[A-Z]/
    return true if known_kind?(current_token.value)

    !colon_glued?
  end

  def known_kind?(name)
    defined?(Archsight::Resources) && !Archsight::Resources[name].nil?
  end

  # Whether the current token starts a name with colons (`ITGS:A001`) that is a bare word, not the start of a
  # condition: the colons touch name characters, and no operator or `?` follows the name
  def colon_glued?
    return false unless @source

    stop = name_run_end(peek_token.position)
    return false unless stop

    following = @tokens.find { |token| token.position >= stop }
    !(following && %i[EQ NEQ MATCH GT LT GTE LTE IN QUESTION].include?(following.type))
  end

  # Where `a:b:c` ends, starting at its first colon; nil when that colon does not touch a name character on both sides
  def name_run_end(colon)
    stop = nil
    while @source[colon] == ":" && colon.positive? && @source[colon - 1].match?(NAME_CHAR)
      word = @source[(colon + 1)..].to_s[/\A#{NAME_CHAR}+/]
      break unless word

      stop = colon + 1 + word.length
      colon = stop
    end
    stop
  end

  def parse_quoted_annotation_path
    # Quoted annotation path: 'scc/language/C++/loc' >= 500
    path = current_token.value
    advance

    # Check if this is followed by an operator (annotation condition) or existence check
    if %i[EQ NEQ MATCH GT LT GTE LTE IN].include?(current_token.type)
      # This is an annotation condition with comparison operator
      parse_annotation_condition_with_path(path)
    elsif current_token.type == :QUESTION
      # Existence check: 'path'?
      advance # consume ?
      Archsight::Query::AST::AnnotationExistsCondition.new(path)
    else
      raise Archsight::Query::ParseError.new(
        "Expected operator or ? after quoted annotation path",
        position: current_token.position,
        source: nil
      )
    end
  end

  def parse_annotation_condition_with_path(path)
    # Parse operator (path already consumed)
    op_token = current_token
    advance

    # Handle IN operator specially
    return parse_in_condition(path) if op_token.type == :IN

    # Parse value
    value_token = current_token
    value = parse_value

    operator = case op_token.type
               when :EQ then "=="
               when :NEQ then "!="
               when :MATCH then "=~"
               when :GT then ">"
               when :LT then "<"
               when :GTE then ">="
               when :LTE then "<="
               end
    check_value(operator, value, value_token)

    Archsight::Query::AST::AnnotationCondition.new(path, operator, value)
  end

  def parse_in_condition(path)
    expect(:LPAREN)

    values = []
    values << parse_in_value

    while current_token.type == :COMMA
      advance # consume comma
      values << parse_in_value
    end

    expect(:RPAREN)

    Archsight::Query::AST::AnnotationInCondition.new(path, values)
  end

  def parse_value
    case current_token.type
    when :STRING
      value = Archsight::Query::AST::StringValue.new(current_token.value)
      advance
      value
    when :NUMBER
      value = Archsight::Query::AST::NumberValue.new(current_token.value)
      advance
      value
    when :REGEX
      data = current_token.value
      value = Archsight::Query::AST::RegexValue.new(data[:pattern], data[:flags])
      advance
      value
    else
      raise Archsight::Query::ParseError.new(
        "Expected value (string, number, or regex)",
        position: current_token.position,
        source: nil
      )
    end
  end

  # A `=~` pattern must compile: report a broken one with the query (and where it starts) instead of
  # when the first resource is checked, which may never happen. A /regex/ literal only means something
  # with `=~`; anywhere else it would silently compare against its pattern text.
  def check_value(operator, value, token)
    if operator == "=~"
      Archsight::Query::AST.regexp_for(value)
    elsif value.is_a?(Archsight::Query::AST::RegexValue)
      raise Archsight::Query::ParseError.new("A /regex/ can only be used with =~, not #{operator}", position: token.position, source: nil)
    end
  rescue Archsight::Query::InvalidRegexError => e
    raise Archsight::Query::InvalidRegexError.new(e.message, position: token.position, source: nil)
  end

  # One value of an `in (...)` list
  def parse_in_value
    token = current_token
    value = parse_value
    check_value("in", value, token)
    value
  end

  def current_token
    @tokens[@position] || @tokens.last
  end

  def peek_token
    @tokens[@position + 1]
  end

  def advance
    @position += 1
  end

  def expect(type)
    unless current_token.type == type
      raise Archsight::Query::ParseError.new(
        "Expected #{type} but got #{current_token.type}",
        position: current_token.position,
        source: nil
      )
    end
    advance
  end
end
