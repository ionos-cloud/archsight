# frozen_string_literal: true

require_relative "../assets"

module Archsight
  module Helpers
    # Loads the diagrams that `include "<path>"` names (see Archsight::Diagram::Includes):
    #
    #   archsight://Kind/name    the `architecture/diagram` of that resource
    #   file://path/to/x.asd     an .asd file, relative to the resources directory (never outside it)
    #
    # #call returns the diagram source, or `:missing` / `:forbidden` / `:invalid`. Without a database only
    # `file://` paths work (the standalone `archsight diagram`).
    class DiagramIncludes
      ARCHSIGHT = "archsight://"
      FILE = "file://"
      ANNOTATION = "architecture/diagram"
      MAX_BYTES = 1_000_000

      # The loader for a database, whose path is the resources directory
      def self.for(database)
        new(database, resources_dir: (database.path if database.respond_to?(:path)))
      end

      def initialize(database, resources_dir:)
        @database = database
        @resources_dir = resources_dir
      end

      def call(path)
        if path.start_with?(ARCHSIGHT)
          resource(path.delete_prefix(ARCHSIGHT))
        elsif path.start_with?(FILE)
          file(path.delete_prefix(FILE))
        else
          :invalid
        end
      end

      private

      # `Kind/name`; names contain `:` but a kind never contains `/`, so the first `/` separates them
      def resource(reference)
        return :forbidden unless @database

        kind, name = reference.split("/", 2)
        return :invalid if kind.to_s.empty? || name.to_s.empty? || !Archsight::Resources[kind]

        source = @database.instance_by_kind(kind, name)&.annotations&.fetch(ANNOTATION, nil)
        source.is_a?(String) && !source.strip.empty? ? source : :missing
      end

      def file(path)
        return :invalid if @resources_dir.nil? || !Archsight::Assets.asd?(path)
        return :forbidden if path.start_with?("/") # file:///etc/x.asd; relative to the resources directory only

        real = Archsight::Assets.file_for(path, resources_dir: @resources_dir)
        return :missing unless real
        return :forbidden if File.size(real) > MAX_BYTES

        File.read(real, encoding: "UTF-8")
      rescue SystemCallError
        :missing
      end
    end
  end
end
