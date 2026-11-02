# frozen_string_literal: true

require "date"
require "digest"
require_relative "typst"
require_relative "markdown"
require_relative "theme"
require_relative "images"
require_relative "embeds"
require_relative "resource_sheet"
require_relative "dependency_graph"
require_relative "../helpers/resource_resolver"
require_relative "../helpers/diagram_includes"
require_relative "../helpers/wiki_links"

module Archsight
  module Pdf
    # One resource or page as the files typst needs: `main.typ` (the document), the layout library, the theme
    # and the images. Pages are exported as written; any other resource becomes a generated document (description,
    # properties, relations, diagram).
    #
    # Tags steer the export (page `page/tags`, resource `architecture/tags`):
    #
    #   pdf:cover               cover page instead of a title block
    #   pdf:toc                 table of contents
    #   pdf:landscape           landscape pages
    #   pdf:draft               "draft" watermark
    #   pdf:no-graph            leave the dependency graph out of a resource document
    #   pdf:template:<name>     pdf Config to use instead of `default`
    #   version:<x>             document version (else the page property Version, else 1)
    class Document
      GRAPH_HEIGHT = 0.8 # share of the page height the dependency graph may take
      LIBRARY = File.join(__dir__, "typst", "archsight.typ")

      # @return [String] title of the document
      attr_reader :title

      # @param template [String, nil] name of a pdf Config, overrides the tag
      # @param draft [Boolean] force the watermark
      def initialize(database, resource, template: nil, draft: false, resources_dir: Archsight.resources_dir, pdf_images: true)
        @database = database
        @resource = resource
        @resources_dir = resources_dir
        @pdf_images = pdf_images
        @tags = tag_list
        @theme = theme_for(template)
        @draft = draft || @tags.include?("pdf:draft")
        @title = title_for
      end

      # @return [Hash{String => String}] file name => content of everything typst needs, `main.typ` among them
      def files
        @files ||= build
      end

      # @return [Array<String>] directories with fonts to hand to typst
      def font_paths
        [@theme.font_dir].compact
      end

      # A name for the downloaded file
      def filename
        "#{@resource.name.to_s.gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/\A[-.]+|-+\z/, "")}.pdf"
      end

      # Changes whenever the PDF would: the files and the fonts
      def fingerprint
        digest = Digest::SHA256.new
        files.sort.each { |name, content| digest << name << "\0" << content.b << "\0" }
        font_paths.each { |dir| Dir.children(dir).sort.each { |f| digest << f << File.size(File.join(dir, f)).to_s } }
        digest.hexdigest[0, 16]
      end

      private

      # The look, the title and the body are what a variant (see SampleDocument) replaces
      def theme_for(template)
        Theme.for(@database, template || tag_value("pdf:template"))
      end

      def title_for
        page? ? @resource.title : @resource.name
      end

      def body(images)
        page? ? page_body(images) : resource_body(images)
      end

      def page?
        @resource.klass == "Page"
      end

      def build
        images = Images.new(base_dir: base_dir, resources_dir: @resources_dir, resolver: resolver,
                            includes: Helpers::DiagramIncludes.for(@database), pdf_images: @pdf_images)
        body = body(images)
        files = { "archsight.typ" => File.read(LIBRARY), "main.typ" => main(body) }.merge(images.files)
        files.merge(logo_files).tap { |f| f["theme.typ"] = @theme.to_typst(**logo_names) }
      end

      def main(body)
        meta = "title: #{Typst.lit(@title)}, doc-id: #{opt(doc_id)}, version: #{opt(version)}, date: #{opt(date)}, owner: #{opt(owner)}"
        args = "theme: theme, #{meta}"
        front = if @tags.include?("pdf:cover")
                  "#cover-page(#{args}, kind: #{opt(kind)}, classification: #{opt(classification)})"
                else
                  "#title-block(theme: theme, title: #{Typst.lit(@title)}, kind: #{opt(kind)})"
                end
        front += "\n#toc-page(theme: theme)" if @tags.include?("pdf:toc")
        <<~TYPST
          #import "archsight.typ": *
          #import "theme.typ": theme
          #show: doc.with(#{args}, classification: #{opt(classification)}, draft: #{@draft}, landscape: #{@tags.include?("pdf:landscape")})
          #{front}

          #{body}
        TYPST
      end

      # ---- body

      def page_body(images)
        markdown(images).render(strip_title(@resource.annotations["page/content"].to_s))
      end

      def resource_body(images)
        ann = @resource.annotations
        sheet = ResourceSheet.new(@resource, markdown: ->(text) { markdown(images, offset: 2).render(text) })
        parts = []
        # the pictures come first, right after the title, then the text and the facts
        parts.concat(dependency_graph(images))
        parts << images.diagram(ann["architecture/diagram"]).to_s if ann["architecture/diagram"].to_s.strip != ""
        parts << markdown(images, offset: 1).render(ann["architecture/description"]) if ann["architecture/description"].to_s.strip != ""
        parts.concat(sheet.properties)
        parts.concat(sheet.relations)
        parts.join("\n\n")
      end

      # The dependency graph the resource's page shows, unless the tag `pdf:no-graph` leaves it out
      def dependency_graph(images)
        return [] if @tags.include?("pdf:no-graph")

        graph = DependencyGraph.new(@database, @resource)
        picture = (images.pdf(graph.pdf, max_height: GRAPH_HEIGHT) if @pdf_images && graph.pdf) ||
                  (images.vector(graph.svg, max_height: GRAPH_HEIGHT) if graph.svg)
        picture ? [picture] : []
      end

      # @param embeds [Boolean] whether views, analyses and `![[..]]` embeds are part of the text; the content of an embed
      #   is rendered without (one level, so embeds cannot include each other)
      def markdown(images, offset: 0, embeds: true)
        links = Helpers::WikiLinks.new(@database, resolver: resolver)
        Markdown.new(heading_offset: offset, image: images.method(:image), diagram: images.method(:diagram), label: links.method(:label_for),
                     embeds: embeds ? embeds_for(images) : nil)
      end

      def embeds_for(images)
        @embeds_for ||= Embeds.new(@database, markdown: ->(inline, text) { markdown(images, offset: 1, embeds: false).render(text, inline: inline) })
      end

      # The header already shows the title, so a leading "# Title" that repeats it is dropped
      def strip_title(body)
        first, rest = body.lstrip.split("\n", 2)
        heading = first.to_s[/\A#\s+(.+?)\s*#*\s*\z/, 1]
        heading && [@title, @resource.name].any? { |t| t.to_s.casecmp?(heading) } ? rest.to_s.lstrip : body
      end

      # ---- metadata

      def properties_hash
        @properties_hash ||= page? ? @resource.properties.to_h : {}
      end

      def tag_list
        raw = @resource.annotations["page/tags"] || @resource.annotations["architecture/tags"]
        raw.to_s.split(",").map(&:strip).reject(&:empty?)
      end

      # `prefix:value` of a tag
      def tag_value(prefix)
        @tags.filter_map { |t| t.delete_prefix("#{prefix}:") if t.start_with?("#{prefix}:") }.first
      end

      def doc_id = properties_hash["Document ID"] || "#{@resource.klass}/#{@resource.name}"
      def version = tag_value("version") || properties_hash["Version"] || "1"
      def classification = properties_hash["Classification"] || @theme.classification
      def kind = page? ? nil : @resource.klass

      def date
        (@resource.annotations["page/updated"] || Date.today.iso8601).to_s[0, 10]
      end

      def owner
        value = @resource.annotations["page/owner"] || @resource.annotations["page/author"] ||
                @resource.annotations["architecture/owner"]
        Annotations::EmailRecipient.parse(value)&.fetch(:name)
      end

      def base_dir
        Assets.base_dir_for(@resource, resources_dir: @resources_dir)
      end

      def resolver
        @resolver ||= Helpers::ResourceResolver.new(@database)
      end

      def opt(value)
        value.to_s.strip.empty? ? "none" : Typst.lit(value)
      end

      # Logos are staged under fixed names; the file type decides the extension
      def logo_names
        { logo: staged_name("logo", @theme.logo), logo_light: staged_name("logo-light", @theme.logo_light) }
      end

      def logo_files
        { logo_names[:logo] => @theme.logo, logo_names[:logo_light] => @theme.logo_light }
          .reject { |name, file| name.nil? || file.nil? }
          .transform_values { |file| File.binread(file) }
      end

      def staged_name(base, file)
        file && "#{base}#{File.extname(file).downcase}"
      end
    end
  end
end
