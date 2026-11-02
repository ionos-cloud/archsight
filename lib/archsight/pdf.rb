# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require_relative "pdf/compiler"
require_relative "pdf/document"

module Archsight
  # PDF export of pages and resources, laid out by Typst (https://typst.app, installed as the `typst` command).
  # See Archsight::Pdf::Document for what steers it and Archsight::Resources::Config (type pdf) for the look.
  module Pdf
    module_function

    # @param resource [Archsight::Resources::Base] a page or any other resource
    # @return [Archsight::Pdf::Document]
    def document(database, resource, compiler: Compiler.new, **)
      Document.new(database, resource, pdf_images: compiler.pdf_images?, **)
    end

    # The PDF of a prepared document
    # @return [String]
    # @raise [Unavailable, Error]
    def compile(document, compiler: Compiler.new)
      Dir.mktmpdir("archsight-pdf") do |dir|
        document.files.each { |name, content| File.binwrite(File.join(dir, name), content) }
        compiler.compile(dir, font_paths: document.font_paths)
      end
    end
  end
end
