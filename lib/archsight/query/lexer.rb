# frozen_string_literal: true

require_relative "errors"

class Archsight::Query::Lexer
  class Token
    attr_reader :type, :value, :position

    def initialize(type, value, position)
      @type = type
      @value = value
      @position = position
    end

    def to_s
      "Token(#{@type}, #{@value.inspect}, pos=#{@position})"
    end
  end

  # Keywords are case-insensitive
  KEYWORDS = {
    "and" => :AND,
    "or" => :OR,
    "not" => :NOT,
    "kind" => :KIND,
    "name" => :NAME,
    "none" => :NONE,
    "in" => :IN
  }.freeze

  # Two-character operators (must be checked before single-character)
  TWO_CHAR_OPERATORS = {
    "==" => :EQ,
    "!=" => :NEQ,
    "=~" => :MATCH,
    ">=" => :GTE,
    "<=" => :LTE,
    "->" => :OUTGOING_DIRECT,
    "~>" => :OUTGOING_TRANSITIVE,
    "<-" => :INCOMING_DIRECT,
    "<~" => :INCOMING_TRANSITIVE
  }.freeze

  # Single-character operators
  SINGLE_CHAR_OPERATORS = {
    ">" => :GT,
    "<" => :LT,
    "&" => :AND,
    "|" => :OR,
    "!" => :NOT
  }.freeze

  def initialize(input)
    @input = input
    @position = 0
    @tokens = []
  end

  def tokenize
    @tokens = []
    while @position < @input.length
      skip_whitespace
      break if @position >= @input.length

      token = scan_token
      @tokens << token if token
    end
    @tokens << Token.new(:EOF, nil, @position)
    @tokens
  end

  private

  def skip_whitespace
    @position += 1 while @position < @input.length && @input[@position] =~ /\s/
  end

  def scan_token
    char = @input[@position]
    start_pos = @position

    case char
    when "("
      @position += 1
      Token.new(:LPAREN, "(", start_pos)
    when ")"
      @position += 1
      Token.new(:RPAREN, ")", start_pos)
    when ":"
      @position += 1
      Token.new(:COLON, ":", start_pos)
    when "$"
      @position += 1
      Token.new(:DOLLAR, "$", start_pos)
    when "?"
      @position += 1
      Token.new(:QUESTION, "?", start_pos)
    when ","
      @position += 1
      Token.new(:COMMA, ",", start_pos)
    when "{"
      @position += 1
      Token.new(:LBRACE, "{", start_pos)
    when "}"
      @position += 1
      Token.new(:RBRACE, "}", start_pos)
    when '"'
      scan_string
    when "'"
      scan_single_quoted_string
    when "/"
      scan_regex
    when "-", "~", "=", "!", ">", "<", "&", "|"
      scan_operator
    else
      if char =~ /[a-zA-Z_]/
        scan_identifier
      elsif char =~ /\d/
        scan_number
      else
        raise Archsight::Query::LexerError.new("Unexpected character '#{char}'", position: @position, source: @input)
      end
    end
  end

  def scan_string
    start_pos = @position
    @position += 1 # skip opening quote
    value = ""

    while @position < @input.length && @input[@position] != '"'
      if @input[@position] == "\\"
        @position += 1
        value += @input[@position] if @position < @input.length
      else
        value += @input[@position]
      end
      @position += 1
    end

    raise Archsight::Query::LexerError.new("Unterminated string", position: start_pos, source: @input) if @position >= @input.length

    @position += 1 # skip closing quote
    Token.new(:STRING, value, start_pos)
  end

  def scan_single_quoted_string
    start_pos = @position
    @position += 1 # skip opening quote
    value = ""

    while @position < @input.length && @input[@position] != "'"
      value += @input[@position]
      @position += 1
    end

    if @position >= @input.length
      raise Archsight::Query::LexerError.new("Unterminated single-quoted string", position: start_pos,
                                                                                  source: @input)
    end

    @position += 1 # skip closing quote
    Token.new(:STRING, value, start_pos)
  end

  def scan_regex
    start_pos = @position
    @position += 1 # skip opening /
    pattern = ""

    while @position < @input.length && @input[@position] != "/"
      pattern += @input[@position]
      if @input[@position] == "\\"
        @position += 1
        pattern += @input[@position] if @position < @input.length
      end
      @position += 1
    end

    raise Archsight::Query::LexerError.new("Unterminated regex", position: start_pos, source: @input) if @position >= @input.length

    @position += 1 # skip closing /

    # Check for flags
    flags = ""
    while @position < @input.length && @input[@position] =~ /[imx]/
      flags += @input[@position]
      @position += 1
    end

    Token.new(:REGEX, { pattern: pattern, flags: flags }, start_pos)
  end

  def scan_operator
    start_pos = @position
    one_char = @input[@position]
    next_char = @position + 1 < @input.length ? @input[@position + 1] : nil

    # Check for verb filter syntax: -{, ~{, <{ should NOT be consumed as two-char operators
    # Instead, emit single char tokens so parser can handle verb filters
    if next_char == "{"
      case one_char
      when "-"
        @position += 1
        return Token.new(:DASH, "-", start_pos)
      when "~"
        @position += 1
        return Token.new(:TILDE, "~", start_pos)
      when "<"
        @position += 1
        return Token.new(:LT, "<", start_pos)
      end
    end

    # Try two-character operators
    if @position + 1 < @input.length
      two_char = @input[@position, 2]
      if TWO_CHAR_OPERATORS[two_char]
        @position += 2
        return Token.new(TWO_CHAR_OPERATORS[two_char], two_char, start_pos)
      end
    end

    # Single character operators
    if SINGLE_CHAR_OPERATORS[one_char]
      @position += 1
      return Token.new(SINGLE_CHAR_OPERATORS[one_char], one_char, start_pos)
    end

    # Handle standalone - and ~ (for verb filter closing: }- and }~)
    if one_char == "-"
      @position += 1
      return Token.new(:DASH, "-", start_pos)
    elsif one_char == "~"
      @position += 1
      return Token.new(:TILDE, "~", start_pos)
    end

    raise Archsight::Query::LexerError.new("Unknown operator '#{one_char}'", position: @position, source: @input)
  end

  def scan_identifier
    start_pos = @position
    value = ""

    # Allow letters, digits, underscores, hyphens, slashes, and dots in identifiers
    # This supports annotation paths like "activity/status" and "scc/language/Go/loc"
    # and resource names like "teleport.e"
    while @position < @input.length && @input[@position] =~ %r{[a-zA-Z0-9_\-/.]}
      value += @input[@position]
      @position += 1
    end

    # Check if it's a keyword (case-insensitive)
    lower = value.downcase
    return Token.new(KEYWORDS[lower], value, start_pos) if KEYWORDS.key?(lower)

    Token.new(:IDENTIFIER, value, start_pos)
  end

  def scan_number
    start_pos = @position
    value = ""

    # Optional negative sign (handled separately as operator, but support here too)
    if @input[@position] == "-"
      value += "-"
      @position += 1
    end

    # Integer part
    while @position < @input.length && @input[@position] =~ /\d/
      value += @input[@position]
      @position += 1
    end

    # Decimal part
    if @position < @input.length && @input[@position] == "."
      value += "."
      @position += 1
      while @position < @input.length && @input[@position] =~ /\d/
        value += @input[@position]
        @position += 1
      end
    end

    Token.new(:NUMBER, value.to_f, start_pos)
  end
end
