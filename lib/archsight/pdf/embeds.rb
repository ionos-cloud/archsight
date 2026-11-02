# frozen_string_literal: true

require "digest"
require_relative "typst"
require_relative "markdown"
require_relative "tables"
require_relative "../view_table"
require_relative "../requirements"
require_relative "../user_config"
require_relative "../helpers/embeds"
require_relative "../helpers/view_blocks"
require_relative "../helpers/requirements_blocks"
require_relative "../helpers/resource_resolver"
require_relative "../query"

module Archsight
  module Pdf
    # The live content of a page, as the data of the moment of the export (as the Confluence export does it): a View
    # (`![[View/Name]]` or a ```view block) and the requirements of some resources as tables, an Analysis as its result,
    # any other resource as its description. Nothing here raises: what cannot be shown is a note in the document, so
    # that nothing disappears silently.
    class Embeds
      MAX_ANALYSES = 5 # per document, an analysis may run for as long as its own timeout
      ANALYSIS_TTL = 60 # seconds a result is reused (the PDF endpoint builds the document for every request)
      ANALYSIS_ENTRIES = 32
      ANALYSIS_HEADING_OFFSET = 2

      @results = {}
      @lock = Mutex.new

      class << self
        # The result of an analysis, from a run of the last minute if there is one
        def result(database, analysis, now: Time.now)
          key = [analysis.name, Digest::SHA256.hexdigest(analysis.annotations.to_a.sort.inspect)]
          entry = @lock.synchronize { @results[key] }
          return entry[:result] if entry && now - entry[:at] < ANALYSIS_TTL

          require_relative "../analysis"
          result = Archsight::Analysis::Executor.new(database).execute(analysis)
          @lock.synchronize do
            @results[key] = { result: result, at: now }
            @results.shift while @results.size > ANALYSIS_ENTRIES
          end
          result
        end
      end

      # @param markdown [#call] `(Boolean inline, String) -> Typst`: renders markdown the way the document does
      def initialize(database, markdown:, max_analyses: nil)
        @database = database
        @markdown = markdown
        @max_analyses = (max_analyses || UserConfig.setting("pdf", "max_analyses") || MAX_ANALYSES).to_i
        @analyses = 0
        @resolver = Helpers::ResourceResolver.new(database)
      end

      def view_block(source)
        table(ViewTable.from_block(@database, source))
      rescue Helpers::ViewBlocks::Error, Archsight::Query::QueryError => e
        problem("view block: #{e.message}")
      end

      def requirements_block(source)
        table(Requirements.table(@database, Helpers::RequirementsBlocks.parse(source)), empty: "No requirements")
      rescue Helpers::RequirementsBlocks::Error, Archsight::Query::QueryError => e
        problem("requirements block: #{e.message}")
      end

      # @param reference [String] `Kind/Name` of `![[Kind/Name]]`
      def embed(reference)
        found = @resolver.find(reference)
        return problem("#{reference}: not found") if found == :missing
        return problem("#{reference}: ambiguous, write Kind/Name") if found == :ambiguous

        kind, name = found
        instance = @database.instance_by_kind(kind, name)
        case kind
        when "View" then view(instance)
        when "Analysis" then analysis(instance)
        else description(kind, instance, reference)
        end
      end

      private

      def table(table, empty: "No results")
        Tables.typst(table, markdown: ->(text) { @markdown.call(true, text) }, empty: empty)
      end

      def problem(message)
        Typst.note(message, fill: "#fde8e8")
      end

      def view(instance)
        table(ViewTable.from_view(@database, instance))
      rescue Helpers::ViewBlocks::Error, Archsight::Query::QueryError => e
        problem("view #{instance.name}: #{e.message}")
      end

      # A page or menu is not content, a resource without description has nothing to show: its name stands there
      def description(kind, instance, reference)
        text = instance.annotations["architecture/description"].to_s.strip
        return Typst.str(reference) unless Helpers::Embeds.embeddable_kind?(kind) && !text.empty?

        @markdown.call(false, text)
      end

      def analysis(instance)
        return problem("Analysis #{instance.name} not run: at most #{@max_analyses} analyses per document") if @analyses >= @max_analyses

        @analyses += 1
        result = self.class.result(@database, instance)
        renderer = Archsight::Analysis::TypstRenderer.new([result], full: true)
        parts = ["#strong[#{Typst.str(instance.name)}]"]
        parts << renderer.error(result) if result.failed?
        parts.concat(result.sections.filter_map { |section| analysis_section(renderer, section) })
        parts.join("\n\n")
      end

      def analysis_section(renderer, section)
        case section[:type]
        when :table then table(analysis_table(section))
        when :text then @markdown.call(false, section[:content].to_s)
        else renderer.section(section, heading_offset: ANALYSIS_HEADING_OFFSET)
        end
      end

      def analysis_table(section)
        rows = section[:rows].map { |row| section[:headers].each_index.map { |i| ViewTable::Cell.new(text: row[i].to_s, as: :markdown) } }
        ViewTable::Table.new(title: "", columns: section[:headers], rows: rows, total: rows.size)
      end
    end
  end
end
