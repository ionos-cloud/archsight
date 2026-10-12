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
        found = find(reference)
        found.is_a?(Array) ? path(*found) : found
      end

      # The resource a reference names.
      # @return [Array(String, String), Symbol] `[kind, name]`, or `:missing` / `:ambiguous`
      def find(reference)
        kind, name = reference.include?("/") ? reference.split("/", 2) : [nil, reference]
        matches = kind ? in_kind(kind, name) : in_any_kind(name)
        return :missing if matches.empty?
        return :ambiguous if matches.length > 1

        matches.first
      end

      # What an annotation that names another resource (`lifecycle/replacedBy`) refers to. A bare `Name` is a
      # resource of the same kind as the annotated one, another kind needs `Kind/Name`.
      # @param value [String] the annotation value
      # @param kind [String] the kind of the annotated resource
      # @return [Array(String, String), Symbol] `[kind, name]`, or `:missing`
      def find_annotated(value, kind)
        reference = value.to_s.strip
        found = find(reference.include?("/") ? reference : "#{kind}/#{reference}")
        found.is_a?(Array) ? found : :missing
      end

      # Where the annotations of a resource that name another resource point to:
      # `{ key => page path }`, `nil` for a reference that does not resolve.
      # @param kind [String] the kind of the annotated resource, which knows the annotation formats
      # @param annotations [Hash]
      def annotation_links(kind, annotations)
        klass = Archsight::Resources[kind]
        annotations.each_with_object({}) do |(key, value), links|
          next unless klass&.annotation_format(key) == :resource

          found = find_annotated(value, kind)
          links[key] = found.is_a?(Array) ? path(*found) : nil
        end
      end

      private

      def in_kind(kind, name)
        klass = Archsight::Resources[kind]
        return [] unless klass && @database.instances.fetch(klass, {}).key?(name)

        [[Archsight::Resources.canonical(kind), name]] # a renamed kind is linked under its new name
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
