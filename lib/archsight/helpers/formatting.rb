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

      # Format number as euro currency
      def to_euro(num)
        rounded = (num * 100).round / 100.0
        parts = format("%.2f", rounded).split(".")
        parts[0] = parts[0].reverse.scan(/\d{1,3}/).join(",").reverse
        "€#{parts.join(".")}"
      end

      # AI-adjusted project estimate configuration
      # Source values stored separately for easy adjustment
      AI_ESTIMATE_CONFIG = {
        cocomo_salary: 150_000,      # COCOMO assumes US salary in USD
        target_salary: 80_000,       # Target salary in EUR
        ai_cost_multiplier: 3.0,     # AI productivity boost for cost
        ai_schedule_multiplier: 2.5, # AI productivity boost for schedule
        ai_team_multiplier: 3.0      # AI productivity boost for team size
      }.freeze

      # Apply AI adjustment factors to project estimates
      # @param type [Symbol] :cost, :schedule, or :team
      # @param value [Numeric, nil] Raw estimate value
      # @return [Numeric, nil] Adjusted value
      def ai_adjusted_estimate(type, value)
        return nil if value.nil?

        cfg = AI_ESTIMATE_CONFIG
        salary_ratio = cfg[:target_salary].to_f / cfg[:cocomo_salary]

        adjusted = case type
                   when :cost
                     value.to_f * salary_ratio / cfg[:ai_cost_multiplier]
                   when :schedule
                     value.to_f / cfg[:ai_schedule_multiplier]
                   when :team
                     (value.to_f / cfg[:ai_team_multiplier]).ceil
                   else
                     raise ArgumentError, "Unknown estimate type: #{type}"
                   end

        type == :team ? adjusted.to_i : adjusted
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
