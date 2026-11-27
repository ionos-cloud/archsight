# frozen_string_literal: true

# What a user writes as text search, turned into a safe FTS5 match expression. Words are ANDed; `OR`, `NOT`,
# parentheses, "phrases" and a trailing `*` (prefix) are FTS5 syntax and kept. Every other token is quoted, so
# `PROJ-1234` or `Archsight:CLI` search for those words next to each other instead of being FTS5 syntax.
module Archsight
  class TextIndex
    module Expression
      TOKEN = /"((?:[^"]|"")*)"(\*)?|[()]|[^\s()"]+/
      OPERATORS = %w[AND OR NOT].freeze
      BAREWORD = /\A[\p{L}\p{N}_]+\z/

      class << self
        # @param prefix [Boolean] every plain word also matches as prefix (search box words while typing)
        # @raise [Archsight::Query::QueryError] when nothing searchable is left
        def translate(text, prefix: false)
          found = tokens(text)
          parts = found.map { |type, token, star| part(type, token, star || (prefix && type == :word)) }
          searchable = found.any? { |type, _, _| %i[word phrase].include?(type) }
          raise Archsight::Query::QueryError.new("Nothing to search for in #{text.inspect}", position: 0, source: nil) unless searchable

          parts.join(" ")
        end

        # The words and phrases that are searched for (not those after NOT), to show where they occur
        def terms(text)
          negated = false
          tokens(text).each_with_object([]) do |(type, token, _), found|
            if type == :operator
              negated = token == "NOT"
            elsif type != :paren
              found << token unless negated
              negated = false
            end
          end
        end

        private

        # [[type, text, star]]: type :phrase, :word, :operator or :paren
        def tokens(text)
          text.to_s.to_enum(:scan, TOKEN).map do
            match = Regexp.last_match
            token = match[0]
            if match[1]
              [:phrase, match[1].gsub('""', '"'), !match[2].nil?]
            elsif %w[( )].include?(token)
              [:paren, token, false]
            elsif OPERATORS.include?(token)
              [:operator, token, false]
            else
              star = token.end_with?("*")
              word = token.delete_suffix("*")
              word.empty? ? nil : [:word, word, star]
            end
          end.compact
        end

        def part(type, token, star)
          case type
          when :paren, :operator then token
          when :phrase then quote(token, star)
          else token.match?(BAREWORD) ? "#{token}#{"*" if star}" : quote(token, star)
          end
        end

        def quote(text, star)
          "\"#{text.gsub('"', '""')}\"#{"*" if star}"
        end
      end
    end
  end
end
