# frozen_string_literal: true

require "thor"
require_relative "version"

module Archsight
  class ModuleCLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "graph PATH", "Print module dependency graph (DOT) for a repository to stdout"
    option :language, aliases: "-l", type: :string, default: "auto",
                      desc: "Language: go, python, java, or auto (default)"
    option :ranksep, type: :numeric, default: 0.6, desc: "Horizontal gap between rank columns"
    option :nodesep, type: :numeric, default: 0.15, desc: "Vertical gap between nodes"
    def graph(path)
      path = File.expand_path(path)
      unless File.directory?(path)
        warn "Error: not a directory: #{path}"
        exit 1
      end

      load_handlers
      handler_classes = resolve_handler(path, options[:language])
      if handler_classes.empty?
        warn "Could not detect language for #{path} — use --language go|python|java"
        exit 1
      end

      require "archsight/import/progress"
      stub = Struct.new(:name, :annotations, :path_ref).new("module-graph", {}, nil)
      any_output = false
      handler_classes.each do |handler_class|
        progress = Archsight::Import::Progress.new(output: $stderr)
        handler = handler_class.new(stub, database: nil, resources_dir: Dir.tmpdir,
                                          progress: progress)
        dot = handler.dot_graph(path: path, ranksep: options[:ranksep],
                                nodesep: options[:nodesep])
        next unless dot

        puts "# #{handler_class.language_name} modules" if handler_classes.size > 1
        puts dot
        any_output = true
      end
      return if any_output

      warn "No modules found in #{path}"
      exit 1
    end

    private

    def load_handlers
      handlers_dir = File.expand_path("import/handlers", __dir__)
      Dir.glob(File.join(handlers_dir, "*.rb")).each { |f| require f }
    end

    def resolve_handler(path, language)
      require "archsight/import/registry"
      if language == "auto" || language.nil?
        Archsight::Import::Registry.handlers_for(path)
      else
        handler = Archsight::Import::Registry.handler_for_language(language)
        warn "Unknown language: #{language}. Use go, python, or java." unless handler
        [handler].compact
      end
    end
  end

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
    option :production, type: :boolean, default: false, desc: "Run in production mode"
    option :disable_reload, type: :boolean, default: false, desc: "Disable the reload button in the UI"
    option :enable_logging, type: :boolean, default: nil, desc: "Enable request logging (default: false in dev, true in prod)"
    option :inline_edit, type: :boolean, default: false, desc: "Enable inline editing (save directly to source files)"
    option :enable_restart, type: :boolean, default: false,
                            desc: "Enable POST /maintenance/restart endpoint (use with imagePullPolicy: Always in Kubernetes)"
    option :restart_token, type: :string, default: nil,
                           desc: "Shared secret required as X-Restart-Token header on POST /maintenance/restart"
    def web
      configure_resources
      require "archsight/web/application"

      env = options[:production] ? :production : :development
      Archsight::Web::Application.configure_environment!(env, logging: options[:enable_logging])
      Archsight::Web::Application.set :reload_enabled, !options[:disable_reload]
      Archsight::Web::Application.set :inline_edit_enabled, options[:inline_edit]

      restart_enabled = options[:enable_restart] || ENV["ARCHSIGHT_RESTART_ENABLED"] == "true"
      restart_token = options[:restart_token] || ENV.fetch("ARCHSIGHT_RESTART_TOKEN", nil)
      Archsight::Web::Application.set :restart_enabled, restart_enabled
      Archsight::Web::Application.set :restart_token, restart_token
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
      # Only load the kinds that import handlers inspect at runtime (ApplicationComponent
      # and ApplicationInterface for GoGrapher/GoDepResolver cross-referencing, BusinessActor
      # for repository handler owner lookup). Validation is disabled because resources may be
      # in an incomplete state during an in-progress import run.
      db = Archsight::Database.new(resources_dir,
                                   verbose: options[:verbose],
                                   only_kinds: %w[Import BusinessActor ApplicationComponent ApplicationInterface],
                                   verify: false)

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

    desc "diagram INPUT...", "Render .asd diagram files to SVG"
    long_desc "Renders each INPUT.asd to an SVG next to it (or to --output for a single input)."
    option :output, aliases: "-o", type: :string, desc: "SVG output path (single input file only)"
    option :watch, aliases: "-w", type: :boolean, desc: "Re-render whenever an input file changes"
    option :relation, type: :string, desc: "Edge relations to draw: comma-separated list, or 'all' (default: dependency,implements)"
    option :style, type: :string, desc: "Generated <style> block: embed it (default), 'none' to omit it, or a URL to link a stylesheet"
    option :theme, type: :string, desc: "Spacing/font-size theme (default: the file's own `theme` statement)"
    option :legend, type: :string, desc: "Legend placement (default: the file's own `legend` statement, else auto)"
    option :profile, aliases: "-p", type: :boolean, desc: "Print stage timing stats after each render"
    def diagram(*inputs)
      require "archsight/diagram/cli"

      diagram = Archsight::Diagram
      relation = options[:relation]
      { theme: [options[:theme], diagram::Theme.names], legend: [options[:legend], diagram::Legend::MODES] }.each do |name, (value, allowed)|
        next if value.nil? || allowed.include?(value)

        warn "Error: invalid --#{name} #{value.inspect} (expected one of: #{allowed.join(", ")})"
        exit 1
      end

      status = diagram::CLI.new.run_with(
        inputs: inputs, output: options[:output], watch: options[:watch], profile: options[:profile],
        style: options[:style], theme: options[:theme], legend: options[:legend],
        relation_filter: if relation.nil?
                           diagram::Relations::DEFAULT_FILTER
                         else
                           (relation == "all" ? diagram::Relations.names : relation.split(","))
                         end
      )
      exit status unless status.zero?
    end

    desc "export [PAGE...]", "Export wiki pages to another system"
    long_desc <<~DESC
      Publishes wiki pages to the system named by --to. With no PAGE, every page that links to a target
      page (for confluence: `confluence: <page URL>` in its frontmatter) is exported. --tag TAG limits the export to pages carrying one of the given tags.

      confluence: a page is only overwritten when Confluence still holds what the last export wrote. Pages
      never exported before, or edited in Confluence since, are reported as blocked and not exported until
      --force. The token is read from ARCHSIGHT_CONFLUENCE_TOKEN or `confluence.token` in
      ~/.config/archsight/archsight.yaml (see --config); `confluence.drawio: true` there (or --drawio) says the
      Confluence has the draw.io app, then diagrams become draw.io macros instead of images. See the Configuration
      page of the documentation. Exits with 1 if a page was blocked or failed.
    DESC
    option :to, type: :string, required: true, desc: "Export target: confluence"
    option :force, type: :boolean, default: false, desc: "Overwrite pages that were edited in the target since the last export"
    option :lock, type: :boolean, default: true, desc: "Restrict editing of exported pages to the exporting user (--no-lock to skip)"
    option :dry_run, type: :boolean, default: false, desc: "Show what would be exported without writing anything"
    option :tag, type: :array, default: [], desc: "Only export pages with at least one of these tags (repeatable, case-insensitive)"
    option :config, type: :string, desc: "Configuration file (default: ARCHSIGHT_CONFIG or ~/.config/archsight/archsight.yaml)"
    option :drawio, type: :boolean, desc: "The target has the draw.io app: export diagrams as draw.io macros, else as images (default: `confluence.drawio` of the configuration)"
    def export(*names)
      configure_resources
      require "archsight/database"
      require "archsight/export"

      db = Archsight::Database.new(Archsight.resources_dir, compute_annotations: false)
      begin
        db.reload!
      rescue Archsight::ResourceError => e
        display_error_with_context(e.to_s)
        exit 1
      end

      settings = nil
      if options[:config]
        require "archsight/export/confluence/credentials"
        settings = Archsight::Export::Confluence::Credentials.load(path: options[:config])
      end
      exporter = Archsight::Export.exporter_for(options[:to]).new(
        database: db, resources_dir: Archsight.resources_dir, force: options[:force], lock: options[:lock],
        dry_run: options[:dry_run], settings: settings, drawio: options[:drawio], tags: options[:tag]
      )
      results = exporter.run(names)
      print_export_results(results)
      exit 1 if results.any? { |r| %i[blocked failed].include?(r.status) }
    rescue Archsight::Export::Error => e
      warn "Error: #{e.message}"
      exit 1
    end

    desc "module SUBCOMMAND", "Module analysis commands (e.g. module graph PATH)"
    subcommand "module", ModuleCLI

    default_task :version

    private

    def print_export_results(results)
      labels = { exported: "exported", would_export: "would export", unchanged: "unchanged", blocked: "NOT EXPORTED (blocked)",
                 skipped: "skipped", failed: "NOT EXPORTED (failed)" }
      width = results.map { |r| labels.fetch(r.status).length }.max.to_i
      results.each { |r| puts "#{labels.fetch(r.status).ljust(width)}  #{r.page}: #{r.message}" }
      counts = results.group_by(&:status).transform_values(&:count)
      puts counts.map { |status, count| "#{count} #{labels.fetch(status)}" }.join(", ") unless results.empty?
      puts "Nothing to export: no page has a `confluence:` link." if results.empty?
    end

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
      analyses
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
