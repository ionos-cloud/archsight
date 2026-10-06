# frozen_string_literal: true

require "yaml"
require_relative "fenced_blocks"

module Archsight
  module Helpers
    # Turns ```view fenced blocks in rendered markdown into inline views: a View defined in place, written as the
    # View resource itself, shown like an embedded `![[View/Name]]`:
    #
    #   ```view
    #   kind: View
    #   metadata:
    #     name: Services without backup      # the title, optional
    #     annotations:
    #       view/query: 'ApplicationService: backup/mode == "none"'
    #       view/fields: name, @owner
    #   ```
    #
    # Like embeds, rendering never runs the query: the block becomes a placeholder carrying the spec, the frontend
    # runs the query. The source stays inside the placeholder for consumers that do not run the frontend (API, MCP).
    #
    # Two steps, like DiagramBlocks, so the query text stays out of the markdown post-processing (URL auto-linking,
    # macros and `[[Name]]` links are plain-text passes over the whole HTML):
    #
    #   html, blocks = ViewBlocks.extract(html)   # blocks -> placeholders
    #   ...further processing of html...
    #   html = ViewBlocks.restore(html, blocks)   # placeholders -> view placeholders / error boxes
    module ViewBlocks
      TYPES = %w[list:name list:name+kind].freeze
      KEYS = %w[view/query view/fields view/sort view/type].freeze

      class Error < StandardError; end

      module_function

      # @return [Array(String, Hash{String => String})] HTML with a placeholder per view block, and the rendered
      #   replacement for each placeholder
      def extract(html)
        FencedBlocks.extract(html, language: "view", prefix: "view-block") { |source, original| render_block(source, original) }
      end

      def restore(html, blocks)
        FencedBlocks.restore(html, blocks, prefix: "view-block")
      end

      # Source of every ```view block in `markdown` (for the linter).
      def sources(markdown)
        FencedBlocks.sources(markdown, language: "view")
      end

      # The View a block describes.
      # @return [Hash] `{ title:, query:, fields: [String], sort: [String], type: String }`
      # @raise [Error] if the block is not a valid View
      def parse(source)
        doc = load(source)
        raise Error, "expected a View resource (a YAML mapping), got #{doc.class.name.downcase}" unless doc.is_a?(Hash)
        raise Error, "kind must be View, not #{doc["kind"].inspect}" if doc.key?("kind") && doc["kind"] != "View"

        annotations = annotations(doc)
        query = annotations["view/query"].to_s.strip
        raise Error, "view/query is missing" if query.empty?

        check_query(query)
        type = annotations["view/type"]&.to_s || TYPES.last
        raise Error, "view/type must be one of #{TYPES.join(", ")}, not #{type.inspect}" unless TYPES.include?(type)

        { title: doc.dig("metadata", "name").to_s, query: query, type: type,
          fields: list(annotations["view/fields"]), sort: list(annotations["view/sort"]) }
      end

      def render_block(source, original)
        spec = parse(source)
        data = { title: spec[:title], query: spec[:query], fields: spec[:fields].join(","), sort: spec[:sort].join(","), type: spec[:type] }
        FencedBlocks.placeholder("view-embed", data, original)
      rescue Error => e
        FencedBlocks.error_box("view-block-error", "View error", e.message, original)
      end

      def load(source)
        FencedBlocks.load_yaml(source)
      rescue Psych::Exception => e
        raise Error, "invalid YAML: #{e.message}"
      end

      def annotations(doc)
        annotations = doc.dig("metadata", "annotations")
        raise Error, "metadata.annotations must be a mapping" unless annotations.nil? || annotations.is_a?(Hash)

        annotations ||= {}
        unknown = annotations.keys.map(&:to_s).select { |key| key.start_with?("view/") } - KEYS
        raise Error, "unknown annotation #{unknown.first.inspect}, a view knows #{KEYS.join(", ")}" unless unknown.empty?

        annotations.transform_keys(&:to_s)
      end

      def check_query(query)
        Archsight::Query.parse(query)
      rescue Archsight::Query::QueryError => e
        raise Error, "invalid query: #{e.message}"
      end

      def list(value)
        value.to_s.split(",").map(&:strip).reject(&:empty?)
      end
    end
  end
end
