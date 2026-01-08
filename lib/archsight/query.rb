# frozen_string_literal: true

# Define the Query namespace before loading query files
# (required for compact class definitions like Archsight::Query::Lexer)
module Archsight::Query; end

require_relative "query/errors"
require_relative "query/ast"
require_relative "query/lexer"
require_relative "query/parser"
require_relative "query/evaluator"

module Archsight
  module Query
    # Main Query class - entry point for parsing and evaluating queries
    class Query
      attr_reader :source, :ast

      def initialize(source)
        @source = source
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
        parser = Parser.new(tokens)
        parser.parse
      rescue LexerError, ParseError => e
        # Re-raise with source context
        raise QueryError.new(e.message, position: e.position, source: source)
      end
    end

    # Convenience method for creating queries
    def self.parse(source)
      Query.new(source)
    end
  end
end
