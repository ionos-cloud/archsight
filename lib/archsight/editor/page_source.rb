# frozen_string_literal: true

require "yaml"
require_relative "../database"
require_relative "../page_loader"
require_relative "file_writer"

module Archsight
  module Editor
    # PageSource renders the markdown file (frontmatter + body) of a Page from editor form values,
    # the counterpart of Editor.to_yaml for kinds that are stored as YAML.
    module PageSource
      # Frontmatter keys the form knows, in the order they are written
      KNOWN_KEYS = %w[title tags author owner status toc confluence].freeze

      module_function

      # @param annotations [Hash] form values keyed by annotation (page/title, ..., page/content)
      # @param existing_source [String, nil] current file content; its `name` and any frontmatter
      #   keys the form does not know are kept (comments and their position are not)
      # @return [String] file content
      def render(annotations:, existing_source: nil)
        extras = existing_meta(existing_source)
        extras.delete_if { |key, _| KNOWN_KEYS.include?(key) }
        lines = []
        lines << scalar_line("name", extras.delete("name")) if extras.key?("name")
        KNOWN_KEYS.each do |key|
          value = annotations["page/#{key}"].to_s.strip
          lines << scalar_line(key, value, raw: key == "toc") unless value.empty?
        end
        lines << YAML.dump(extras).sub(/\A---\s*\n/, "").delete_prefix("{}\n") unless extras.empty?

        "---\n#{lines.join}---\n#{body(annotations["page/content"])}"
      end

      # Check that a submitted file still is the page it replaces
      # @raise [FileWriter::WriteError]
      def validate!(source, path:, name:)
        raw = PageLoader.build(path: path, source: source, ref: LineReference.new(path, 1))
        raise FileWriter::WriteError, "A page needs a frontmatter block (--- ... ---)" unless raw
        return if raw.dig("metadata", "name") == name

        raise FileWriter::WriteError, "The page name must stay '#{name}' (set by the file name or `name:`)"
      rescue ResourceError => e
        raise FileWriter::WriteError, "Invalid frontmatter: #{e.message}"
      end

      # Blank line after the frontmatter, single trailing newline
      def body(content)
        text = content.to_s.gsub("\r\n", "\n").rstrip
        text = "\n#{text}" unless text.start_with?("\n")
        "#{text}\n"
      end

      def existing_meta(source)
        return {} unless source && PageLoader.frontmatter?(source)

        match = PageLoader::FRONTMATTER.match(source)
        meta = match && YAML.safe_load(match[:meta], permitted_classes: [Date, Time])
        meta.is_a?(Hash) ? meta.transform_keys(&:to_s) : {}
      rescue Psych::SyntaxError
        {}
      end

      # `key: value` with the value quoted only when YAML needs it (toc is written as yes/no)
      def scalar_line(key, value, raw: false)
        text = value.to_s
        text = text.include?("\n") ? text.to_json : YAML.dump(text, line_width: -1).sub(/\A--- /, "").sub(/\n(\.\.\.\n)?\z/, "") unless raw
        "#{key}: #{text}\n"
      end
    end
  end
end
