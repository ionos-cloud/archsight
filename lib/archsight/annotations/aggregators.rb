# frozen_string_literal: true

# ComputedAggregators provides static methods for aggregating annotation values.
# These functions handle nil values gracefully and convert types as needed.
module Archsight::Annotations::ComputedAggregators
  class << self
    # Sum numeric values
    # @param values [Array] Array of values to sum
    # @return [Float, nil] Sum of values converted to float, nil if no valid values
    def sum(values)
      numeric_values = to_numeric(values)
      return nil if numeric_values.empty?

      numeric_values.sum
    end

    # Count non-nil values
    # @param values [Array] Array of values to count
    # @return [Integer] Count of non-nil values
    def count(values)
      values.compact.length
    end

    # Calculate average of numeric values
    # @param values [Array] Array of values to average
    # @return [Float, nil] Average of values, nil if no valid values
    def avg(values)
      numeric_values = to_numeric(values)
      return nil if numeric_values.empty?

      numeric_values.sum / numeric_values.length.to_f
    end

    # Find minimum numeric value
    # @param values [Array] Array of values
    # @return [Float, nil] Minimum value, nil if no valid values
    def min(values)
      numeric_values = to_numeric(values)
      return nil if numeric_values.empty?

      numeric_values.min
    end

    # Find maximum numeric value
    # @param values [Array] Array of values
    # @return [Float, nil] Maximum value, nil if no valid values
    def max(values)
      numeric_values = to_numeric(values)
      return nil if numeric_values.empty?

      numeric_values.max
    end

    # Collect unique values, flattening arrays and sorting
    # @param values [Array] Array of values (may contain nested arrays)
    # @return [Array] Unique sorted values
    def collect(values)
      flat_values = values.flatten.compact
      # Handle comma-separated strings (list annotations)
      expanded = flat_values.flat_map do |v|
        v.is_a?(String) ? v.split(",").map(&:strip) : v
      end
      expanded.compact.uniq.sort_by(&:to_s)
    end

    # Get first non-nil value
    # @param values [Array] Array of values
    # @return [Object, nil] First non-nil value
    def first(values)
      values.compact.first
    end

    # Find most common value (mode)
    # @param values [Array] Array of values (may contain nested arrays)
    # @return [Object, nil] Most frequent value, nil if no values
    def most_common(values)
      flat_values = values.flatten.compact
      return nil if flat_values.empty?

      # Handle comma-separated strings (list annotations)
      expanded = flat_values.flat_map do |v|
        v.is_a?(String) ? v.split(",").map(&:strip) : v
      end

      expanded.compact
              .group_by(&:itself)
              .max_by { |_, group| group.length }
              &.first
    end

    private

    # Convert values to numeric (float), filtering out non-convertible values
    def to_numeric(values)
      values.compact.filter_map do |v|
        case v
        when Numeric
          v.to_f
        when String
          begin
            Float(v)
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
