# frozen_string_literal: true

require "open3"
require_relative "typst"
require_relative "remote_image"
require_relative "../assets"
require_relative "../diagram"
require_relative "../helpers/diagram_blocks"

module Archsight
  module Pdf
    # The pictures of a document: images next to the markdown and `asd` diagrams, copied (or converted) into the
    # directory typst compiles in. Only what Archsight::Assets serves is ever read.
    class Images
      RASTER = %w[.png .jpg .jpeg .gif].freeze

      # @return [Hash{String => String}] staged file name => content
      attr_reader :files

      # @param base_dir [String, nil] directory of the markdown file, relative to the resources directory
      # @param pdf_images [Boolean] whether typst can place PDF files; else vector graphics stay SVG
      def initialize(base_dir:, resources_dir:, resolver: nil, includes: nil, pdf_images: true, remote: RemoteImage.method(:fetch))
        @base_dir = base_dir.to_s
        @resources_dir = resources_dir
        @resolver = resolver
        @includes = includes
        @pdf_images = pdf_images
        @remote = remote && RemoteImage.enabled? ? remote : nil
        @files = {}
      end

      # Hook for Markdown: Typst markup of the image a markdown reference names, nil if it cannot be shown
      def image(src, _alt = nil)
        return remote(src) if Assets.external?(src)

        path = Assets.resolve_reference(src, @base_dir)
        file = path && Assets.file_for(path, resources_dir: @resources_dir)
        return nil unless file && File.size(file) <= Assets::MAX_BYTES

        case File.extname(file).downcase
        when *RASTER then place(File.binread(file), File.extname(file).downcase)
        when ".svg" then vector(File.read(file, encoding: "UTF-8"))
        when ".asd" then diagram(File.read(file, encoding: "UTF-8"))
        when Assets::DRAWIO then Typst.note("draw.io diagram, shown in Archsight", fill: "#f2f2f2")
        end
      end

      # Hook for Markdown: Typst markup of an `asd` diagram, or a note and the source if it does not render
      def diagram(source)
        vector(Helpers::DiagramBlocks.standalone_svg(source, resolver: @resolver, includes: @includes))
      rescue Archsight::Diagram::Error => e
        note = Typst.note("Diagram could not be rendered: #{e.message}", fill: "#fde8e8")
        [note, Typst.raw(source, "asd")].join("\n\n")
      end

      # Vector graphics are placed as PDF (rsvg-convert paints text outlines correctly, typst's own SVG renderer
      # does not honour `paint-order`), as SVG when that tool or PDF images are not available.
      def vector(svg, max_height: nil)
        pdf = @pdf_images ? Images.svg_to_pdf(svg) : nil
        pdf ? place(pdf, ".pdf", max_height: max_height) : place(svg, ".svg", max_height: max_height)
      end

      # A PDF page that is already a picture (drawn by another tool), placed as it is
      def pdf(bytes, max_height: nil)
        place(bytes, ".pdf", max_height: max_height)
      end

      # @return [String, nil] PDF bytes of an SVG document, nil without rsvg-convert
      def self.svg_to_pdf(svg)
        out, status = Open3.capture2("rsvg-convert", "--format", "pdf", stdin_data: svg, binmode: true)
        status.success? && !out.empty? ? out : nil
      rescue Errno::ENOENT
        nil
      end

      # An image by URL: fetched when allowed, else the caller shows the alt text
      def remote(src)
        return nil unless @remote && src.match?(%r{\Ahttps?://}i)

        bytes, ext = @remote.call(src)
        place(bytes, ext) if bytes
      end

      private

      # @param max_height [Float, nil] share of the page height the picture may take (the layout's default if nil)
      def place(bytes, ext, max_height: nil)
        name = "img-#{@files.size + 1}#{ext}"
        @files[name] = bytes
        "#fit-image(#{Typst.lit(name)}#{", max-height: #{max_height}" if max_height})"
      end
    end
  end
end
