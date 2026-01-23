# frozen_string_literal: true

require "timeout"
require_relative "sandbox"
require_relative "result"

module Archsight
  module Analysis
    # Executor runs Analysis scripts in a sandboxed environment with timeout enforcement
    class Executor
      # Default timeout in seconds
      DEFAULT_TIMEOUT = 30

      # Duration parsing patterns
      DURATION_PATTERNS = {
        /^(\d+)s$/ => 1,
        /^(\d+)m$/ => 60,
        /^(\d+)h$/ => 3600
      }.freeze

      attr_reader :database

      # @param database [Archsight::Database] Loaded database instance
      def initialize(database)
        @database = database
      end

      # Execute an Analysis resource
      # @param analysis [Archsight::Resources::Analysis] Analysis to execute
      # @return [Archsight::Analysis::Result] Execution result
      def execute(analysis)
        script = analysis.annotations["analysis/script"]
        timeout_seconds = parse_timeout(analysis.annotations["analysis/timeout"])

        return Result.new(analysis, success: false, error: "No script defined") if script.nil? || script.empty?

        sandbox = Sandbox.new(@database)
        sandbox._set_analysis(analysis)

        start_time = Time.now
        begin
          Timeout.timeout(timeout_seconds) do
            # Execute script in sandbox context
            # Using instance_eval ensures script only has access to sandbox methods
            sandbox.instance_eval(script, "analysis:#{analysis.name}", 1)
          end

          duration = Time.now - start_time
          Result.new(
            analysis,
            success: true,
            sections: sandbox.sections,
            duration: duration
          )
        rescue Timeout::Error
          Result.new(
            analysis,
            success: false,
            error: "Execution timed out after #{timeout_seconds}s",
            sections: sandbox.sections
          )
        rescue StandardError, SyntaxError => e
          Result.new(
            analysis,
            success: false,
            error: "#{e.class}: #{e.message}",
            error_backtrace: e.backtrace&.first(5),
            sections: sandbox.sections
          )
        end
      end

      # Execute all enabled Analysis resources
      # @param filter [Regexp, nil] Optional filter for analysis names
      # @return [Array<Archsight::Analysis::Result>] Array of results
      def execute_all(filter: nil)
        analyses = @database.instances_by_kind("Analysis").values

        # Filter by name pattern if provided
        analyses = analyses.select { |a| filter.match?(a.name) } if filter

        analyses.map { |analysis| execute(analysis) }
      end

      private

      # Parse timeout string to seconds
      # @param timeout_str [String, nil] Timeout string (e.g., "30s", "5m")
      # @return [Integer] Timeout in seconds
      def parse_timeout(timeout_str)
        return DEFAULT_TIMEOUT if timeout_str.nil? || timeout_str.empty?

        DURATION_PATTERNS.each do |pattern, multiplier|
          match = timeout_str.match(pattern)
          return match[1].to_i * multiplier if match
        end

        DEFAULT_TIMEOUT
      end
    end
  end
end
