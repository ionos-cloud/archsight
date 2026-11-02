# frozen_string_literal: true

require_relative "document"

module Archsight
  module Pdf
    # A fixed sample document in the look of one pdf Config, to see what the settings do without exporting a real page:
    # a cover page and a page with the elements a document is made of (headings, text, list, quote, table with
    # status, code). The content is neutral on purpose; only the Config shapes the result. The "resource" of the document
    # is the Config (an Archsight::Resources::Config of type pdf).
    class SampleDocument < Document
      PARTS = %w[cover page].freeze
      TITLE = "Sample document"
      BODY = <<~MD
        ## Summary

        This page shows how headings, text, lists and tables look with the settings of the Config. It is a fixed sample,
        not one of your documents, so every change of a colour, a font or the logo is visible at once.

        > A quote stands out from the text around it and is set in the same typeface.

        ### What a document contains

        - Text with **strong** and *emphasised* words, `inline code` and a [link](https://example.com)
        - Lists, tables, diagrams and code, set in the fonts of the Config
        - Status badges such as {status:green Active} and {status:yellow Planned}

        ## Components

        | Component | Owner | Status |
        |:----------|:------|:-------|
        | Billing API | Payments | {status:green Active} |
        | Export service | Data | {status:yellow Deprecated} |
        | Legacy gateway | Platform | {status:red End of life} |

        ### Interface

        ```ruby
        def total(items)
          items.sum(&:price)
        end
        ```
      MD

      # @param part [String, nil] `cover` or `page` for just that page (a document of one page, so a viewer needs no
      #   navigation), else both
      def initialize(database, config, part: nil, **)
        @part = part if PARTS.include?(part)
        super(database, config, **)
      end

      def filename = "#{["preview", super.delete_suffix(".pdf"), @part].compact.join("-")}.pdf"

      private

      def theme_for(_template) = Theme.new(@resource, resources_dir: @resources_dir)
      def title_for = TITLE
      def tag_list = @part == "page" ? [] : %w[pdf:cover]
      def body(images) = @part == "cover" ? "" : markdown(images).render(BODY)
      def doc_id = "SAMPLE-001"
      def version = "1.0"
      def owner = "Alex Example"
      def kind = "Sample"
      def classification = @theme.classification
    end
  end
end
