# frozen_string_literal: true

require "thor"

module Archsight
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    class_option :resources,
                 aliases: "-r",
                 type: :string,
                 desc: "Path to resources directory (default: ARCHSIGHT_RESOURCES_DIR or current directory)"

    desc "web", "Start the web server"
    option :port, aliases: "-p", type: :numeric, default: 4567, desc: "Port to listen on"
    option :host, aliases: "-H", type: :string, default: "localhost", desc: "Host to bind to"
    option :disable_reload, type: :boolean, default: false, desc: "Disable the reload button in the UI"
    def web
      configure_resources
      require "archsight/web/application"
      Archsight::Web::Application.set :reload_enabled, !options[:disable_reload]
      Archsight::Web::Application.setup_mcp!
      Archsight::Web::Application.run!(port: options[:port], bind: options[:host])
    rescue Archsight::ResourceError => e
      display_error_with_context(e.to_s)
      exit 1
    end

    desc "lint", "Validate architecture resources"
    def lint
      configure_resources
      require "archsight/database"
      require "archsight/linter"
      require "archsight/helpers"

      db = Archsight::Database.new(Archsight.resources_dir, compute_annotations: false, verbose: true)
      begin
        db.reload!
      rescue Archsight::ResourceError => e
        display_error_with_context(e.to_s)
        exit 1
      end

      linter = Archsight::Linter.new(db)
      errors = linter.validate

      if errors.any?
        puts "Validation Errors (#{errors.count}):"
        errors.each { |error| display_error_with_context(error) }
        exit 1
      end

      puts "All validations passed!"
    end

    desc "template [KIND]", "Generate a YAML template for a resource kind"
    def template(kind = nil)
      require "archsight/template"
      require "archsight/resources"

      if kind.nil?
        list_kinds
      else
        puts Archsight::Template.generate(kind)
      end
    end

    desc "console", "Start an interactive console"
    def console
      configure_resources
      require "archsight/database"
      require "irb"

      db = Archsight::Database.new(Archsight.resources_dir, verbose: true)
      db.reload!

      puts "Database loaded. Available: db"
      binding.irb
    end

    desc "import", "Execute pending imports"
    option :verbose, aliases: "-v", type: :boolean, default: false, desc: "Verbose output"
    option :dry_run, aliases: "-n", type: :boolean, default: false, desc: "Show execution plan without running"
    option :filter, aliases: "-f", type: :string, desc: "Filter imports by name (regex pattern)"
    option :force, aliases: "-F", type: :boolean, default: false, desc: "Ignore cache and re-run all imports"
    def import
      configure_resources
      require "archsight/database"
      require "archsight/import/executor"

      resources_dir = Archsight.resources_dir

      # Load all handlers
      require_import_handlers

      # Create database that loads from resources directory
      # Only load Import resources to avoid validation errors on incomplete resources
      db = Archsight::Database.new(resources_dir, verbose: options[:verbose], only_kinds: ["Import"], verify: false)

      if options[:dry_run]
        puts "Execution Plan:"
        executor = Archsight::Import::Executor.new(
          database: db,
          resources_dir: resources_dir,
          verbose: true,
          filter: options[:filter],
          force: options[:force]
        )
        executor.execution_plan
      else
        executor = Archsight::Import::Executor.new(
          database: db,
          resources_dir: resources_dir,
          verbose: options[:verbose],
          filter: options[:filter],
          force: options[:force]
        )
        executor.run!
        puts "All imports completed successfully."
      end
    rescue Archsight::Import::InterruptedError
      # Graceful shutdown already handled by executor
      exit 130
    rescue Archsight::Import::DeadlockError => e
      puts "Error: #{e.message}"
      exit 1
    rescue Archsight::Import::ImportError => e
      puts "Error: #{e.message}"
      exit 1
    rescue Archsight::ResourceError => e
      display_error_with_context(e.to_s)
      exit 1
    end

    desc "analyze", "Execute analysis scripts"
    option :verbose, aliases: "-v", type: :boolean, default: false, desc: "Verbose output"
    option :dry_run, aliases: "-n", type: :boolean, default: false, desc: "List analyses without running"
    option :filter, aliases: "-f", type: :string, desc: "Filter analyses by name (regex pattern)"
    def analyze
      configure_resources
      require "archsight/database"
      require "archsight/analysis"

      db = load_database_for_analysis
      analyses = filter_analyses(db)

      return puts("No analyses found#{" matching '#{options[:filter]}'" if options[:filter]}.") if analyses.empty?
      return print_analysis_dry_run(analyses) if options[:dry_run]

      results = execute_analyses(db, analyses)
      print_analysis_results(results)
      exit 1 if results.any?(&:failed?)
    end

    desc "version", "Show version"
    def version
      puts "archsight #{Archsight::VERSION}"
    end

    default_task :version

    private

    def configure_resources
      Archsight.resources_dir = options[:resources] if options[:resources]
    end

    def require_import_handlers
      handlers_dir = File.expand_path("import/handlers", __dir__)
      Dir.glob(File.join(handlers_dir, "*.rb")).each do |handler_file|
        require handler_file
      end
    end

    def load_database_for_analysis
      db = Archsight::Database.new(Archsight.resources_dir, verbose: options[:verbose])
      db.reload!
      db
    rescue Archsight::ResourceError => e
      display_error_with_context(e.to_s)
      exit 1
    end

    def filter_analyses(db)
      analyses = db.instances_by_kind("Analysis").values
      analyses = analyses.select { |a| Regexp.new(options[:filter], Regexp::IGNORECASE).match?(a.name) } if options[:filter]
      analyses.reject { |a| a.annotations["analysis/enabled"] == "false" }
    end

    def print_analysis_dry_run(analyses)
      puts "Analyses to run#{" (filter: #{options[:filter]})" if options[:filter]}:"
      analyses.sort_by(&:name).each_with_index do |analysis, idx|
        timeout = analysis.annotations["analysis/timeout"] || "30s"
        desc = analysis.annotations["analysis/description"] || "(no description)"
        puts "  #{idx + 1}. #{analysis.name} [#{timeout}]"
        puts "     #{desc}"
      end
    end

    def execute_analyses(db, analyses)
      executor = Archsight::Analysis::Executor.new(db)
      analyses.map { |analysis| executor.execute(analysis) }
    end

    def print_analysis_results(results)
      require "tty-markdown"

      results.each do |result|
        print_single_result(result)
        puts ""
      end

      summary_md = build_analysis_summary_markdown(results)
      puts TTY::Markdown.parse(summary_md)
    end

    def print_single_result(result)
      # Print status header
      header = "# #{result.status_emoji} #{result.name}"
      header += " (#{result.duration_str})" unless result.duration_str.empty?
      puts TTY::Markdown.parse(header)

      # Print error if failed
      puts TTY::Markdown.parse(result.error_markdown(verbose: options[:verbose])) if result.failed?

      # Print script output
      output = result.to_s(verbose: options[:verbose])
      puts output unless output.empty?
    end

    def build_analysis_summary_markdown(results)
      passed = results.count(&:success?)
      failed = results.count(&:failed?)
      with_findings = results.count(&:has_findings?)

      lines = ["---", "", "# Summary", ""]
      lines << "- ✅ **#{passed}** passed"
      lines << "- ❌ **#{failed}** failed" if failed.positive?
      lines << "- ⚠️ **#{with_findings}** with findings" if with_findings.positive?
      lines.join("\n")
    end

    def list_kinds
      puts "Available resource kinds:\n\n"
      Archsight::Resources.resource_classes.each_key { |kind| puts "  - #{kind}" }
      puts "\nUsage: archsight template <kind>"
    end

    def display_error_with_context(error_string)
      # Parse error to extract file path and line number
      if error_string =~ /^(.+?):(\d+):/
        file_path = ::Regexp.last_match(1)
        line_number = ::Regexp.last_match(2).to_i
        puts "\n#{error_string}"
        show_file_context(file_path, line_number)
      else
        puts error_string
      end
    end

    def show_file_context(file_path, line_number, context_lines: 3)
      return unless File.exist?(file_path)

      lines = File.readlines(file_path)
      start_line = [line_number - context_lines - 1, 0].max
      end_line = [line_number + context_lines - 1, lines.length - 1].min

      puts ""
      (start_line..end_line).each do |i|
        line_num = i + 1
        prefix = line_num == line_number ? ">> " : "   "
        puts format("%s%4d | %s", prefix, line_num, lines[i])
      end
      puts ""
    end
  end
end
