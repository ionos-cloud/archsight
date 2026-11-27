# frozen_string_literal: true

require_relative "ast"

# Regex search over the string annotations of a resource (`text =~ /x/`, `text(keys) =~ "x"`); where a text
# condition matched is shown by Archsight::TextIndex::Snippets.
module Archsight::Query::TextSearch
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
  end
end
