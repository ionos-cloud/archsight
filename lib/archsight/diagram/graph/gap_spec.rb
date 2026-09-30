# frozen_string_literal: true

module Archsight
  module Diagram
    # Parses a node's `gap` attr -- an absolute pixel value ("40"), a plain
    # percentage of a default ("150%"), or a relative delta with an
    # explicit sign ("+20%"/"-50%") -- into a value object that knows how
    # to apply itself against whatever default gap the caller would
    # otherwise use (see `Graph::Node#gap`).
    class GapSpec
      def self.parse(raw)
        new(raw)
      end

      def initialize(raw)
        @raw = raw
      end

      # `default` untouched if no `gap` attr was set at all (the
      # overwhelming common case); otherwise the parsed absolute/
      # percentage/relative value, never negative.
      def apply(default)
        return default unless @raw
        return [@raw.to_f, 0.0].max unless @raw.end_with?("%")

        percent = @raw.to_f
        relative = @raw.start_with?("+", "-")
        value = relative ? default + (default * percent / 100.0) : default * (percent / 100.0)
        [value, 0.0].max
      end
    end
  end
end
