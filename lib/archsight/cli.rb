# frozen_string_literal: true

require "thor"

module Archsight
  class CLI < Thor
    class_option :resources,
                 aliases: "-r",
                 type: :string,
                 desc: "Path to resources directory (default: ARCHSIGHT_RESOURCES_DIR or current directory)"

    desc "web", "Start the web server"
    option :port, aliases: "-p", type: :numeric, default: 4567, desc: "Port to listen on"
    option :host, aliases: "-H", type: :string, default: "localhost", desc: "Host to bind to"
    def web
      configure_resources
      require "archsight/web/application"
      Archsight::Web::Application.run!(port: options[:port], bind: options[:host])
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

    desc "version", "Show version"
    def version
      puts "archsight #{Archsight::VERSION}"
    end

    default_task :version

    private

    def configure_resources
      Archsight.resources_dir = options[:resources] if options[:resources]
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
