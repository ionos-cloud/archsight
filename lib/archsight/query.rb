# frozen_string_literal: true

# Define the Query namespace before loading query files
# (required for compact class definitions like Archsight::Query::Lexer)
module Archsight::Query; end

require_relative "query/errors"
require_relative "query/ast"
require_relative "query/lexer"
require_relative "query/parser"
require_relative "query/text_search"
require_relative "query/evaluator"
require_relative "text_index"

module Archsight
  module Query
    # Main Query class - entry point for parsing and evaluating queries
    class Query
      attr_reader :source, :ast

      # @param bare_words [Symbol] :name (default) or :search, see Parser
      def initialize(source, bare_words: :name)
        @source = source
        @bare_words = bare_words
        @ast = parse(source)
      end

      # Check if a single instance matches this query
      def matches?(instance, database:)
        evaluator = Evaluator.new(database)
        evaluator.matches?(@ast, instance)
      end

      # Filter all instances from database matching this query
      def filter(database)
        evaluator = Evaluator.new(database)
        evaluator.filter(@ast)
      end

      # The matching instances ordered by relevance when the query searches text (full-text conditions, search box
      # words), else as #filter returns them
      def ranked(database)
        evaluator = Evaluator.new(database)
        evaluator.rank(@ast, evaluator.filter(@ast))
      end

      # [[instance, relevance]] best first when the query searches text, nil otherwise
      def scored(database)
        evaluator = Evaluator.new(database)
        evaluator.scored(@ast, evaluator.filter(@ast))
      end

      # Whether the order of #ranked is a relevance order (the query searches text)
      def ranked?
        !FullText.ranking_nodes(@ast).empty?
      end

      # Return the kind filter if present (for optimization)
      def kind_filter
        @ast.kind_filter
      end

      # Pretty print for debugging
      def to_s
        "Query(#{@source})"
      end

      def inspect
        "#<Query source=#{@source.inspect} kind_filter=#{kind_filter.inspect}>"
      end

      private

      def parse(source)
        lexer = Lexer.new(source)
        tokens = lexer.tokenize
        parser = Parser.new(tokens, source: source, bare_words: @bare_words)
        parser.parse
      rescue LexerError, ParseError, InvalidRegexError => e
        # Re-raise with source context
        raise QueryError.new(e.message, position: e.position, source: source)
      end
    end

    # Convenience method for creating queries
    def self.parse(source, bare_words: :name)
      Query.new(source, bare_words: bare_words)
    end
  end
end
