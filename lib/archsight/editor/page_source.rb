# frozen_string_literal: true

require "yaml"
require "time"
require_relative "../database"
require_relative "../page_loader"
require_relative "file_writer"

module Archsight
  module Editor
    # PageSource renders the markdown file (frontmatter + body) of a Page from editor form values,
    # the counterpart of Editor.to_yaml for kinds that are stored as YAML.
    module PageSource
      # Frontmatter keys the form knows, in the order they are written
      KNOWN_KEYS = %w[title tags author owner status toc confluence created updated properties].freeze
      TIMESTAMPS = %w[created updated].freeze
      ISO_TIMESTAMP = /\A\d{4}-\d{2}-\d{2}(?:T[\d:.]+(?:Z|[+-]\d\d:\d\d))?\z/

      module_function

      # @param annotations [Hash] form values keyed by annotation (page/title, ..., page/content)
      # @param existing_source [String, nil] current file content; its `name` and any frontmatter
      #   keys the form does not know are kept (comments and their position are not)
      # @param now [Time, nil] when given and the page changes, `updated` is set to it
      # @return [String] file content
      def render(annotations:, existing_source: nil, now: nil)
        source = render_fields(annotations, existing_source)
        return source unless now && existing_source && source != existing_source

        render_fields(annotations.merge("page/updated" => now.utc.iso8601), existing_source)
      end

      def render_fields(annotations, existing_source)
        extras = existing_meta(existing_source)
        extras.delete_if { |key, _| KNOWN_KEYS.include?(key) }
        lines = []
        lines << scalar_line("name", extras.delete("name")) if extras.key?("name")
        KNOWN_KEYS.each do |key|
          value = annotations["page/#{key}"].to_s.strip
          next if value.empty?

          lines << (key == "properties" ? properties_lines(value) : scalar_line(key, value, raw: key == "toc" || (TIMESTAMPS.include?(key) && value.match?(ISO_TIMESTAMP))))
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

      # The `Key: value` lines of the form as a YAML mapping
      def properties_lines(text)
        pairs = text.lines.filter_map do |line|
          key, value = line.chomp.split(/:\s*/, 2)
          [key.strip, value.to_s.strip] unless key.to_s.strip.empty?
        end
        "properties:\n#{YAML.dump(pairs.to_h).sub(/\A---\s*\n/, "").gsub(/^/, "  ")}"
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
