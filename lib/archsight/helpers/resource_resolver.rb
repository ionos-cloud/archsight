# frozen_string_literal: true

require "erb"

module Archsight
  module Helpers
    # Resolves a diagram node's `resource "..."` reference against the
    # resource database (see Archsight::Diagram::ResourceLinks): `Name`
    # looks the name up across all kinds, `Kind/Name` in one kind (names
    # contain `:`, so `/` separates the kind).
    #
    # #call returns the resource's page path, `:missing` when there is no
    # such resource, or `:ambiguous` when a bare name exists in several kinds.
    class ResourceResolver
      def initialize(database)
        @database = database
      end

      def call(reference)
        kind, name = reference.include?("/") ? reference.split("/", 2) : [nil, reference]
        matches = kind ? in_kind(kind, name) : in_any_kind(name)
        return :missing if matches.empty?
        return :ambiguous if matches.length > 1

        path(*matches.first)
      end

      private

      def in_kind(kind, name)
        klass = Archsight::Resources[kind]
        return [] unless klass && @database.instances.fetch(klass, {}).key?(name)

        [[kind, name]]
      end

      def in_any_kind(name)
        @database.instances.filter_map { |klass, by_name| [klass.to_s.split("::").last, name] if by_name.key?(name) }
      end

      # `:` stays readable (it is how every name is written); the rest is escaped
      def path(kind, name)
        "/kinds/#{kind}/instances/#{ERB::Util.url_encode(name).gsub("%3A", ":")}"
      end
    end
  end
end
