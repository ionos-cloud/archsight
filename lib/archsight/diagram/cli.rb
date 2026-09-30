# frozen_string_literal: true

require "optparse"
require_relative "."

module Archsight
  module Diagram
    class CLI
      def self.run(argv)
        new.run(argv)
      end

      def run(argv)
        options = parse_options(argv)
        return 1 unless options

        run_with(options)
      end

      # Runs with already-parsed options (:inputs, :output, :watch, :relation_filter,
      # :style, :theme, :legend, :profile), e.g. from the `archsight diagram` Thor command.
      def run_with(options)
        if options[:inputs].empty?
          warn "archsight-diagram: missing input file\n\n#{usage}"
          return 1
        end

        if options[:output] && options[:inputs].length > 1
          warn "archsight-diagram: -o/--output can only be used with a single input file\n\n#{usage}"
          return 1
        end

        if options[:watch]
          watch(options)
          0
        else
          statuses = options[:inputs].map do |input|
            render_once(input, output_for(input, options[:output]), options)
          end
          statuses.all?(&:zero?) ? 0 : 1
        end
      end

      private

      def parse_options(argv)
        options = { output: nil, watch: false, inputs: [], relation_filter: Relations::DEFAULT_FILTER,
                    profile: false, style: nil, theme: nil, legend: nil }

        parser = OptionParser.new do |opts|
          opts.banner = usage
          opts.on("-o OUTPUT", "--output OUTPUT", "SVG output path (single input file only; " \
                                                  "default: each input with a .svg extension)") do |v|
            options[:output] = v
          end
          opts.on("-w", "--watch", "Re-render whenever an input file changes") do
            options[:watch] = true
          end
          opts.on("--relation=LIST", "Which edge relations to draw: comma-separated " \
                                     "#{Relations.names.join(",")}, or 'all' (default: dependency,implements)") do |v|
            options[:relation_filter] = v == "all" ? Relations.names : v.split(",")
          end
          opts.on("--style=STYLE", "The generated <style> block: embed it (default), 'none' to omit it " \
                                   "entirely, or a URL to link an external stylesheet instead") do |v|
            options[:style] = v
          end
          opts.on("--theme=NAME", Theme.names, "Spacing/font-size theme: #{Theme.names.join(", ")} " \
                                               "(default: the file's own `theme` statement, else default)") do |v|
            options[:theme] = v
          end
          opts.on("--legend=MODE", Legend::MODES, "Where to put the legend: #{Legend::MODES.join(", ")} " \
                                                  "(default: the file's own `legend` statement, else auto -- " \
                                                  "right of a tall diagram, below a wide one)") do |v|
            options[:legend] = v
          end
          opts.on("-p", "--profile", "Print stage timing stats after each render") do
            options[:profile] = true
          end
          opts.on("-h", "--help", "Show this help") do
            puts opts
            exit 0
          end
        end

        options[:inputs] = parser.parse(argv)
        options
      rescue OptionParser::ParseError => e
        warn "archsight-diagram: #{e.message}\n\n#{usage}"
        nil
      end

      def usage
        "Usage: archsight-diagram INPUT.asd [INPUT2.asd ...] [-o OUTPUT.svg] [--watch] [--relation=LIST] [--style=STYLE] [--theme=NAME] [--legend=MODE] [-p]"
      end

      def output_for(input, explicit_output)
        explicit_output || default_output_for(input)
      end

      def default_output_for(input)
        "#{input.sub(/\.[^.]+\z/, "")}.svg"
      end

      def render_once(input, output, options)
        profile = options[:profile]
        stats = profile ? {} : nil
        total_start = Process.clock_gettime(Process::CLOCK_MONOTONIC) if profile

        svg = Archsight::Diagram.render(File.read(input), relation_filter: options[:relation_filter], profile: stats,
                                                          style: options[:style], theme: options[:theme], legend: options[:legend])

        write_start = Process.clock_gettime(Process::CLOCK_MONOTONIC) if profile
        File.write(output, svg)
        stats[:write] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - write_start if profile

        puts "archsight-diagram: wrote #{output}"
        print_stats(stats, total_start) if profile
        0
      rescue Archsight::Diagram::Error => e
        warn "archsight-diagram: #{input}: #{e.message}"
        1
      rescue Errno::ENOENT => e
        warn "archsight-diagram: #{e.message}"
        1
      end

      def print_stats(stats, total_start)
        total = Process.clock_gettime(Process::CLOCK_MONOTONIC) - total_start
        parts = stats.map { |key, seconds| "#{key}=#{format("%.1fms", seconds * 1000)}" }
        parts << "total=#{format("%.1fms", total * 1000)}"
        puts "archsight-diagram:   #{parts.join(" ")}"
      end

      def watch(options)
        inputs = options[:inputs]
        label = inputs.length == 1 ? inputs.first : "#{inputs.length} files"
        puts "archsight-diagram: watching #{label} (Ctrl-C to stop)"
        last_mtimes = {}

        loop do
          inputs.each do |input|
            mtime = File.exist?(input) ? File.mtime(input) : nil
            next unless mtime && mtime != last_mtimes[input]

            last_mtimes[input] = mtime
            render_once(input, output_for(input, options[:output]), options)
          end
          sleep 0.5
        end
      rescue Interrupt
        puts "\narchsight-diagram: stopped watching"
      end
    end
  end
end
