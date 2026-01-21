# frozen_string_literal: true

module Archsight
  module Helpers
    # Formatting provides string and number formatting utilities
    module Formatting
      module_function

      # Convert string to class name format
      def classify(val)
        val.to_s.split("-").map(&:capitalize).join
      end

      # Format number as dollar currency
      def to_dollar(num)
        rounded = (num * 100).round / 100.0
        parts = format("%.2f", rounded).split(".")
        parts[0] = parts[0].reverse.scan(/\d{1,3}/).join(",").reverse
        "$#{parts.join(".")}"
      end

      # Convert git URL to HTTPS URL
      def http_git(repo_url)
        repo_url.gsub(/.git$/, "")
                .gsub(":", "/")
                .gsub("git@", "https://")
      end

      # Format number with thousands delimiter
      def number_with_delimiter(num)
        num.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
      end

      # Convert timestamp to human-readable relative time
      def time_ago(timestamp)
        return nil unless timestamp

        time = timestamp.is_a?(Time) ? timestamp : Time.parse(timestamp.to_s)
        seconds = (Time.now - time).to_i

        units = [
          [60, "second"],
          [60, "minute"],
          [24, "hour"],
          [7, "day"],
          [4, "week"],
          [12, "month"],
          [Float::INFINITY, "year"]
        ]

        value = seconds
        units.each do |divisor, unit|
          return "just now" if unit == "second" && value < 10
          return "#{value} #{unit}#{"s" if value != 1} ago" if value < divisor

          value /= divisor
        end
      end
    end
  end
end
