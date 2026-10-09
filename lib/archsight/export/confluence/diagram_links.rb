# frozen_string_literal: true

require_relative "page_url"

module Archsight
  module Export
    module Confluence
      # Resolves the `resource "..."` references of a diagram for the export. The web UI links them to Archsight
      # pages, which mean nothing in Confluence; here a reference to a wiki page that has a Confluence page links
      # to that page, and every other existing resource stays a plain node.
      #
      # Quacks like Helpers::ResourceResolver for Diagram::ResourceLinks: a URL, nil (no link), :missing, :ambiguous.
      class DiagramLinks
        def initialize(database, resolver: Helpers::ResourceResolver.new(database))
          @database = database
          @resolver = resolver
        end

        def call(reference)
          found = @resolver.find(reference)
          return found unless found.is_a?(Array)

          kind, name = found
          kind == "Page" ? confluence_url(@database.instances_by_kind("Page")[name]) : nil
        end

        # @return [String, nil] where the page lives in Confluence, nil if it has no Confluence page
        def self.confluence_url(page)
          link = page&.annotations&.fetch("link/confluence", nil).to_s.strip
          return nil if link.empty?

          parsed = PageUrl.parse(link)
          parsed.page_id ? parsed.view_url : link
        rescue ArgumentError
          nil
        end

        private

        def confluence_url(page) = self.class.confluence_url(page)
      end
    end
  end
end
