# frozen_string_literal: true

module Archsight
  # References derives relations from what the text and the diagrams of resources say, so that nobody has to repeat in
  # YAML what is already written:
  #
  # - `mentions`: `[[Target]]`, `[[Kind/Name]]` and `![[View/Name]]` in a markdown text (a page's content, the
  #   description of any resource, any annotation a kind defines as markdown)
  # - `depicts`: the `resource "..."` of the nodes of a diagram: an ```asd block in such a text, an `.asd` file embedded
  #   with `![](file.asd)`, and the `architecture/diagram` annotation of any resource
  #
  # The relations are added to the resources like written ones (see Base#add_derived_relation), after the written ones
  # are resolved, and are rebuilt on every load. Only what names a resource exactly counts: a target that is missing,
  # ambiguous or only matches part of a name is skipped (the linter reports the broken ones), and so are links in code.
  # Views and requirements blocks select resources with a query when they run, so they name nothing.
  module References
    # A fenced code block, and an inline code span: links in them are shown as written
    FENCE = /^[ \t]*(?:```|~~~).*?^[ \t]*(?:```|~~~)[ \t]*$/m
    INLINE_CODE = /`[^`\n]*`/

    # Annotations that are markdown besides those a kind defines with `format: :markdown`
    MARKDOWN_KEYS = %w[page/content architecture/description].freeze

    module_function

    # Adds the derived relations to every resource of the database.
    def derive!(database)
      finder = Finder.new(database)
      database.instances.values.flat_map(&:values).each do |inst|
        text_sources(inst).each { |markdown| mentions(markdown, finder).each { |target| link(inst, :mentions, target) } }
        diagram_sources(inst, database).each { |source| depictions(source, finder).each { |target| link(inst, :depicts, target) } }
      end
    end

    # The resources a markdown text mentions with `[[...]]` links and `![[View/...]]` embeds, outside code.
    # @return [Array<Base>]
    def mentions(markdown, finder)
      visible = markdown.to_s.gsub(FENCE, "").gsub(INLINE_CODE, "")
      embeds = visible.scan(Helpers::Embeds::PATTERN).flatten.map(&:strip).filter_map { |reference| finder.embed(reference) }
      targets = visible.gsub(Helpers::Embeds::PATTERN, "").scan(Helpers::WikiLinks::PATTERN).map { |match| match.first.strip }
      (embeds + targets.filter_map { |target| finder.link(target) }).uniq
    end

    # The resources the nodes of a diagram source name with `resource "..."`; a source that is not a valid diagram
    # names none.
    # @return [Array<Base>]
    def depictions(source, finder)
      Diagram.resource_references(source).filter_map { |reference| finder.reference(reference) }
    rescue Diagram::Error
      []
    end

    # The markdown texts of a resource: a page's content, the description, and every annotation its kind defines as
    # markdown.
    def text_sources(inst)
      inst.annotations.filter_map do |key, value|
        value if value.is_a?(String) && value.include?("[[") && markdown_annotation?(inst, key)
      end
    end

    # The diagram sources of a resource: ```asd blocks and embedded `.asd` files of its markdown texts, and its
    # annotations that are diagrams (`architecture/diagram`).
    def diagram_sources(inst, database)
      sources = [] #: Array[String]
      inst.annotations.each do |key, value|
        next unless value.is_a?(String)

        if inst.class.annotation_format(key) == :asd
          sources << value
        elsif markdown_annotation?(inst, key)
          sources.concat(Helpers::DiagramBlocks.sources(value))
          sources.concat(embedded_diagrams(inst, value, database)) if value.include?(".asd")
        end
      end
      sources
    end

    def markdown_annotation?(inst, key)
      MARKDOWN_KEYS.include?(key) || inst.class.annotation_format(key) == :markdown
    end

    # The sources of the `.asd` files a markdown text embeds, found next to the file the resource comes from
    def embedded_diagrams(inst, markdown, database)
      resources_dir = database.path.to_s
      base_dir = Assets.base_dir_for(inst, resources_dir: resources_dir)
      return [] unless base_dir

      Helpers::AssetImages.asd_files(markdown, base_dir: base_dir, resources_dir: resources_dir).filter_map do |_path, file|
        File.read(file) if File.size(file) <= Helpers::AssetImages::MAX_ASD
      end
    rescue SystemCallError
      []
    end

    def link(inst, verb, target)
      return if target.equal?(inst)

      inst.add_derived_relation(verb, target)
    end

    # Finds the resource a reference in a text names, exactly (see WikiLinks#exact_target_for)
    class Finder
      def initialize(database)
        @database = database
        @resolver = Helpers::ResourceResolver.new(database)
        @links = Helpers::WikiLinks.new(database, resolver: @resolver)
      end

      # A `[[...]]` target: a page by name or title, `Kind/Name`, or a resource name
      def link(target)
        @links.exact_target_for(target)
      end

      # An `![[Kind/Name]]` embed: only views and analyses can be embedded
      def embed(reference)
        kind = reference.split("/", 2).first
        return unless Helpers::Embeds::KINDS.include?(kind)

        reference(reference)
      end

      # A `resource "..."` of a diagram or an embed: `Name` across all kinds, or `Kind/Name`
      def reference(reference)
        found = @resolver.find(reference)
        found.is_a?(Array) ? @database.instances_by_kind(found.first)[found.last] : nil
      end
    end
  end
end
