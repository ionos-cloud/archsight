# frozen_string_literal: true

require "date"
require "time"
require "yaml"

module Archsight
  # PageLoader turns a markdown file with YAML frontmatter into the raw resource
  # hash of a Page, so pages flow through the same Database code path as YAML resources.
  module PageLoader
    FRONTMATTER = /\A---[ \t]*\r?\n(?<meta>.*?)\r?\n?^---[ \t]*\r?$\n?(?<body>.*)\z/m

    module_function

    # Whether the markdown source starts with a frontmatter block
    def frontmatter?(source)
      source.match?(/\A---[ \t]*\r?\n/)
    end

    # Build the raw Page hash for a markdown file.
    # @param path [String] file path
    # @param source [String] file content
    # @param ref [LineReference] reference used for error reporting
    # @return [Hash, nil] nil if the file has no frontmatter (plain markdown is ignored)
    def build(path:, source:, ref:)
      return nil unless frontmatter?(source)

      match = FRONTMATTER.match(source) ||
              Kernel.raise(ResourceError.new("frontmatter is not closed with ---", ref))
      meta = parse_meta(match[:meta], ref)

      {
        "apiVersion" => "architecture/v1alpha1",
        "kind" => "Page",
        "metadata" => {
          "name" => (meta.delete("name") || default_name(path)).to_s,
          "annotations" => annotations(meta, match[:body])
        },
        "spec" => {}
      }
    end

    # Name derived from the file name only, so it does not depend on the directory the tool is
    # started in: "strategy/language-strategy.md" -> "language-strategy". Files with the same
    # name in different folders need an explicit `name:` (the Database reports the clash).
    def default_name(path)
      File.basename(path, File.extname(path))
    end

    def parse_meta(text, ref)
      meta = YAML.safe_load(text, permitted_classes: [Date, Time]) || {}
      Kernel.raise(ResourceError.new("frontmatter must be a mapping", ref)) unless meta.is_a?(Hash)

      meta.transform_keys(&:to_s)
    rescue Psych::SyntaxError => e
      # line 1 is the opening ---
      Kernel.raise(ResourceError.new(e.problem || e.message, ref.at_line((e.line || 0) + 1)))
    end

    def annotations(meta, body)
      result = {} #: Hash[String, String]
      meta.each do |key, value|
        next if value.nil?

        if key == "links" && value.is_a?(Hash)
          links(value).each { |name, url| result["link/#{name}"] = url }
        else
          result["page/#{key}"] = format_value(key, value)
        end
      end
      result["page/content"] = body
      result
    end

    # `links: { confluence: <url> }` of the frontmatter: one link/<name> annotation per entry
    def links(mapping)
      mapping.each_with_object({}) do |(name, url), result|
        result[name.to_s] = url.to_s unless url.nil?
      end
    end

    def format_value(key, value)
      case value
      when Hash then value.map { |k, v| "#{k}: #{v.to_s.gsub(/\s*\n\s*/, " ")}" }.join("\n")
      when Time then value.utc.iso8601
      when Date then value.iso8601
      when Array then value.join(", ")
      when true then key == "toc" ? "yes" : "true"
      when false then key == "toc" ? "no" : "false"
      else value.to_s
      end
    end
  end
end
