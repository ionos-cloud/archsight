# frozen_string_literal: true

require_relative "diagram"
require_relative "helpers/diagram_blocks"
require_relative "helpers/asset_images"

module Archsight
  # Estimated reading time of a markdown page: its words plus the diagrams (fenced ```asd blocks and embedded
  # .asd files), which take longer the more nodes and edges they have.
  module ReadingTime
    WORDS_PER_MINUTE = 200
    CODE_WEIGHT = 0.5 # code is read, but slower to count: every code word counts this much
    SECONDS_PER_DIAGRAM = 10
    SECONDS_PER_NODE = 3
    SECONDS_PER_EDGE = 2

    FENCE = /^[ \t]*(```|~~~)[^\n]*\n.*?^[ \t]*\1[ \t]*$/m
    WORD = /\p{L}[\p{L}\p{N}'’-]*|\p{N}+/
    MARKUP = /!\[[^\]]*\]\([^)]*\)|<[^>]+>|\{[a-z]+:[^}]*\}|https?:\/\/\S+/

    # @return [Hash] `{ minutes:, words:, diagrams: }`; minutes is rounded up, at least 1
    def self.estimate(markdown, base_dir: nil, resources_dir: nil, includes: nil)
      markdown = markdown.to_s
      prose, code = split(markdown)
      words = count(prose)
      sources = Helpers::DiagramBlocks.sources(markdown) + embedded(markdown, base_dir, resources_dir)
      seconds = (words + (count(code) * CODE_WEIGHT)) * 60.0 / WORDS_PER_MINUTE
      seconds += sources.sum { |source| diagram_seconds(source, includes) }
      { minutes: [(seconds / 60.0).ceil, 1].max, words: words, diagrams: sources.size }
    end

    # Splits the markdown into prose and the text of non-diagram code blocks (diagram blocks are counted separately).
    def self.split(markdown)
      code = []
      prose = markdown.gsub(FENCE) do |block|
        code << block unless block.match?(/\A[ \t]*(?:```|~~~)asd\b/)
        " "
      end
      [prose.gsub(MARKUP, " "), code.join("\n")]
    end
    private_class_method :split

    def self.count(text)
      text.scan(WORD).size
    end
    private_class_method :count

    def self.embedded(markdown, base_dir, resources_dir)
      return [] unless resources_dir

      Helpers::AssetImages.asd_files(markdown, base_dir: base_dir, resources_dir: resources_dir).filter_map do |_path, file|
        source = File.read(file, encoding: "UTF-8") if File.size(file) <= Helpers::AssetImages::MAX_ASD
        source if source&.valid_encoding?
      end
    end
    private_class_method :embedded

    def self.diagram_seconds(source, includes)
      graph = Diagram::Graph.build(Diagram.expand(source, includes: includes).statements)
      SECONDS_PER_DIAGRAM + (graph.nodes_by_id.size * SECONDS_PER_NODE) + (graph.edges.size * SECONDS_PER_EDGE)
    rescue Diagram::Error
      SECONDS_PER_DIAGRAM
    end
    private_class_method :diagram_seconds
  end
end
