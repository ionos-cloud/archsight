# frozen_string_literal: true

require "yaml"
require_relative "fenced_blocks"

module Archsight
  module Helpers
    # Turns ```requirements fenced blocks in rendered markdown into the table of business requirements of a
    # selection of resources (see Archsight::Requirements):
    #
    #   ```requirements
    #   title: Requirements of the backup services     # optional
    #   of: 'ApplicationService: name =~ "Backup"'     # required: query selecting the resources
    #   priority: must                                 # optional: must, should, may (one or a list)
    #   status: [implemented, partial]                 # optional: implemented, partial, planned
    #   ```
    #
    # Like views and embeds, rendering never runs the query: the block becomes a placeholder carrying the filter and
    # the frontend asks the API (`GET /api/v1/requirements`). The source stays inside the placeholder for consumers
    # that do not run the frontend (API, MCP). Extract and restore like DiagramBlocks, see FencedBlocks.
    module RequirementsBlocks
      KEYS = %w[title of priority status].freeze

      class Error < StandardError; end

      module_function

      def extract(html)
        FencedBlocks.extract(html, language: "requirements", prefix: "requirements-block") { |source, original| render_block(source, original) }
      end

      def restore(html, blocks)
        FencedBlocks.restore(html, blocks, prefix: "requirements-block")
      end

      # Source of every ```requirements block in `markdown` (for the linter).
      def sources(markdown)
        FencedBlocks.sources(markdown, language: "requirements")
      end

      # The filter a block describes.
      # @return [Hash] `{ title:, of:, priority: [String], status: [String] }`
      # @raise [Error] if the block is not a valid filter
      def parse(source)
        doc = load(source)
        raise Error, "expected a mapping with `of`, got #{doc.class.name.downcase}" unless doc.is_a?(Hash)

        unknown = doc.keys.map(&:to_s) - KEYS
        raise Error, "unknown key #{unknown.first.inspect}, known are #{KEYS.join(", ")}" unless unknown.empty?

        of = doc["of"].to_s.strip
        raise Error, "`of` is missing: the query selecting the resources" if of.empty?

        check_query(of)
        { title: doc["title"].to_s, of: of,
          priority: values(doc["priority"], Archsight::Requirements::PRIORITIES, "priority"),
          status: values(doc["status"], Archsight::Requirements::STATUSES.values, "status") }
      end

      def render_block(source, original)
        spec = parse(source)
        data = { title: spec[:title], of: spec[:of], priority: spec[:priority].join(","), status: spec[:status].join(",") }
        FencedBlocks.placeholder("requirements-embed", data, original)
      rescue Error => e
        FencedBlocks.error_box("requirements-block-error", "Requirements error", e.message, original)
      end

      def load(source)
        FencedBlocks.load_yaml(source)
      rescue Psych::Exception => e
        raise Error, "invalid YAML: #{e.message}"
      end

      def check_query(query)
        Archsight::Query.parse(query)
      rescue Archsight::Query::QueryError => e
        raise Error, "invalid query: #{e.message}"
      end

      # A scalar or a list, each value one of `allowed`
      def values(value, allowed, name)
        list = Array(value).map { |v| v.to_s.strip }.reject(&:empty?)
        invalid = list - allowed
        raise Error, "#{name} must be #{allowed.join(", ")}, not #{invalid.first.inspect}" unless invalid.empty?

        list
      end
    end
  end
end
