# frozen_string_literal: true

require_relative "ast"

# Free-text search over the string annotations of a resource (`text =~ "x"`), shared by the evaluator and by the
# MCP query tool, which shows where the text was found.
module Archsight::Query::TextSearch
  SNIPPET_WIDTH = 60

  class << self
    # Yields [key, value, MatchData] for every string annotation of `instance` the condition matches
    def each_match(instance, condition, &block)
      return enum_for(:each_match, instance, condition) unless block

      regex = condition.regexp
      keys = condition.key_patterns
      instance.annotations.each do |key, value|
        next unless value.is_a?(String)
        next if keys&.none? { |pattern| pattern.match?(key) }

        match = regex.match(value)
        block.call(key, value, match) if match
      end
    end

    def matches?(instance, condition)
      !each_match(instance, condition).first.nil?
    end

    # A short single-line excerpt of `value` around the match
    def snippet(value, match, width: SNIPPET_WIDTH)
      from = [match.begin(0) - width, 0].max
      to = [match.end(0) + width, value.length].min
      text = value[from...to].gsub(/\s+/, " ").strip
      "#{"…" if from.positive?}#{text}#{"…" if to < value.length}"
    end
  end
end
