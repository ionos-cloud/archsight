# frozen_string_literal: true

module Archsight
  module Analysis
    # Result represents the outcome of an Analysis execution
    class Result
      attr_reader :analysis, :success, :error, :error_backtrace, :sections, :duration

      # @param analysis [Object] The Analysis resource that was executed
      # @param success [Boolean] Whether execution completed successfully
      # @param error [String, nil] Error message if execution failed
      # @param error_backtrace [Array<String>, nil] Backtrace if execution failed
      # @param sections [Array<Hash>] Output sections generated during execution
      # @param duration [Float, nil] Execution duration in seconds
      def initialize(analysis, success:, error: nil, error_backtrace: nil, sections: [], duration: nil)
        @analysis = analysis
        @success = success
        @error = error
        @error_backtrace = error_backtrace
        @sections = sections || []
        @duration = duration
      end

      # @return [Boolean] true if execution succeeded
      def success?
        @success
      end

      # @return [Boolean] true if execution failed
      def failed?
        !@success
      end

      # @return [String] Analysis name
      def name
        @analysis.name
      end

      # @return [Boolean] true if any content sections exist (excluding messages)
      def has_findings?
        @sections.any? { |s| %i[table list text heading code].include?(s[:type]) }
      end

      # @return [Integer] Count of error-level messages
      def error_count
        @sections.count { |s| s[:type] == :message && s[:level] == :error }
      end

      # @return [Integer] Count of warning-level messages
      def warning_count
        @sections.count { |s| s[:type] == :message && s[:level] == :warning }
      end

      # Convert result to markdown (only script-generated content)
      # @param verbose [Boolean] Include detailed output
      # @return [String] Markdown formatted output
      def to_markdown(verbose: false)
        format_sections_markdown(verbose).compact.join("\n\n")
      end

      # Render markdown for CLI display using tty-markdown
      # @param verbose [Boolean] Include detailed output
      # @return [String] Rendered output for terminal
      def render(verbose: false)
        require "tty-markdown"
        md = to_markdown(verbose: verbose)
        md.empty? ? "" : TTY::Markdown.parse(md)
      rescue LoadError
        # Fallback to plain markdown if tty-markdown not available
        to_markdown(verbose: verbose)
      end

      # Format result for console output (backward compatible)
      # @param verbose [Boolean] Include detailed output
      # @return [String] Formatted output
      def to_s(verbose: false)
        render(verbose: verbose)
      end

      # Status emoji for display
      # @return [String] Status emoji
      def status_emoji
        return "❌" unless success?

        has_findings? ? "⚠️" : "✅"
      end

      # Formatted duration string
      # @return [String] Duration string or empty
      def duration_str
        @duration ? format("%.2fs", @duration) : ""
      end

      # Error details as markdown (for CLI to use if needed)
      # @param verbose [Boolean] Include backtrace
      # @return [String, nil] Error markdown or nil
      def error_markdown(verbose: false)
        return nil unless failed?

        lines = ["**Error:** #{@error}"]
        if verbose && @error_backtrace&.any?
          lines << ""
          lines << "```"
          lines.concat(@error_backtrace)
          lines << "```"
        end
        lines.join("\n")
      end

      private

      def format_sections_markdown(verbose)
        @sections.map { |section| format_section_markdown(section, verbose) }.compact
      end

      def format_section_markdown(section, verbose)
        case section[:type]
        when :message then format_message_markdown(section)
        when :heading then format_heading_markdown(section)
        when :text then section[:content]
        when :table then format_table_markdown(section, verbose)
        when :list then format_list_markdown(section, verbose)
        when :code then format_code_markdown(section)
        end
      end

      def format_message_markdown(section)
        emoji = { error: "🔴", warning: "🟡", info: "🔵" }.fetch(section[:level], "ℹ️")
        "#{emoji} #{section[:message]}"
      end

      def format_heading_markdown(section)
        "#{"#" * (section[:level] + 1)} #{section[:text]}"
      end

      def format_table_markdown(section, verbose)
        headers = section[:headers]
        rows = section[:rows]

        # Limit rows if not verbose
        display_rows = verbose ? rows : rows.first(10)
        truncated = !verbose && rows.size > 10

        lines = []
        lines << "| #{headers.join(" | ")} |"
        lines << "| #{headers.map { "---" }.join(" | ")} |"
        display_rows.each do |row|
          lines << "| #{row.map { |cell| cell.to_s.gsub("|", "\\|") }.join(" | ")} |"
        end
        lines << "_...and #{rows.size - 10} more rows_" if truncated

        lines.join("\n")
      end

      def format_list_markdown(section, verbose)
        items = section[:items]

        # Limit items if not verbose
        display_items = verbose ? items : items.first(10)
        truncated = !verbose && items.size > 10

        lines = display_items.map { |item| "- #{item}" }
        lines << "_...and #{items.size - 10} more items_" if truncated

        lines.join("\n")
      end

      def format_code_markdown(section)
        lang = section[:lang] || ""
        "```#{lang}\n#{section[:content]}\n```"
      end
    end
  end
end
