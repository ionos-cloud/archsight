# frozen_string_literal: true

# Base error class for all query-related errors
class Archsight::Query::QueryError < StandardError
  attr_reader :position, :source

  def initialize(message, position: nil, source: nil)
    @position = position
    @source = source
    super(message)
  end

  def to_s
    if @position && @source
      line_info = extract_line_info
      "#{super}\n#{line_info}"
    else
      super
    end
  end

  private

  def extract_line_info
    return "" unless @source && @position

    pointer = "#{" " * @position}^"
    "  #{@source}\n  #{pointer}"
  end
end

# Error during lexical analysis (tokenization)
class Archsight::Query::LexerError < Archsight::Query::QueryError; end

# Error during parsing
class Archsight::Query::ParseError < Archsight::Query::QueryError; end

# Error during query evaluation
class Archsight::Query::EvaluationError < Archsight::Query::QueryError; end
