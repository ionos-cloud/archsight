# frozen_string_literal: true

require_relative "markdown_text"

module Archsight
  module Diagram
    # A label's line-splitting/measurement heuristic, shared by every place
    # that needs to estimate how much room a (possibly multi-line) label
    # needs before it's actually rendered: node-box sizing
    # (`Layout#leaf_size`), overlap-avoiding label placement
    # (`Renderer::LabelPlacer.label_bbox`), and the real `<tspan>` layout
    # (`Renderer::TextRenderer#text_content_markup`). Each caller supplies
    # its own char-width/line-height (font size and context vary), but the
    # line-splitting and "how many extra lines" arithmetic is identical
    # everywhere it's used.
    module TextMetrics
      module_function

      # `text.split("\n")`, normalized so a blank label still measures/
      # renders as one empty line, never zero. Each line of a
      # `MarkdownText` stays one.
      def lines(text)
        split = text.split("\n")
        return [""] if split.empty?

        text.is_a?(MarkdownText) ? split.map { |line| MarkdownText.new(line) } : split
      end

      def longest_line_length(text)
        lines(text).map(&:length).max
      end

      def width(text, char_width:)
        longest_line_length(text) * char_width
      end

      # Helvetica's (and Arial's -- metric-compatible) advance widths, in
      # 1/1000 em, for printable ASCII (" " through "~", indexed by
      # `ord - 32`), from Adobe's core-font AFM files. Anything outside
      # that range falls back to `FALLBACK_WIDTH`, a deliberately generous
      # guess (an em dash is 1000, most accented letters match their base).
      HELVETICA_WIDTHS = [
        278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
        1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
        333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
        556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584
      ].freeze
      HELVETICA_BOLD_WIDTHS = [
        278, 333, 474, 556, 556, 889, 722, 238, 333, 333, 389, 584, 278, 333, 278, 278,
        556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 333, 333, 584, 584, 584, 611,
        975, 722, 722, 722, 722, 667, 611, 778, 722, 278, 556, 722, 611, 833, 722, 778,
        667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 333, 278, 333, 584, 556,
        333, 556, 611, 556, 611, 556, 333, 611, 611, 278, 278, 556, 278, 889, 611, 611,
        611, 611, 389, 556, 333, 611, 556, 778, 556, 556, 500, 389, 280, 389, 584
      ].freeze
      FALLBACK_WIDTH = 700

      # The rendered width, in px, of `text`'s widest line at `font_size`
      # -- markdown-lite markers don't take up room, and `**bold**` runs
      # are measured with the bold widths. Much tighter than
      # `width(text, char_width:)`'s flat per-char estimate, which has to
      # budget every char as if it were a wide one.
      def rendered_width(text, font_size:)
        lines(text).map { |line| line_units(line) }.max * font_size / 1000.0
      end

      def line_units(line)
        markdown_runs(line).sum do |content, style|
          table = style[:bold] ? HELVETICA_BOLD_WIDTHS : HELVETICA_WIDTHS
          content.each_char.sum do |char|
            index = char.ord - 32
            index.between?(0, table.length - 1) ? table[index] : FALLBACK_WIDTH
          end
        end
      end

      # A small, deliberately non-nested markdown-lite: `**bold**`,
      # `*italic*`, `__underline__` (a separate marker from bold's `**` so
      # the two never collide, since real Markdown has no underline
      # syntax), and `[text](url)` for an inline link. Scans left to
      # right, splitting `text` into `[content, style]` pairs -- `style`
      # is `{}` for a plain run. Only a `MarkdownText` is scanned (the lexer
      # flags every string literal a marker could start in); any other
      # string comes back as a single `[text, {}]` run.
      def markdown_runs(text)
        return text.empty? ? [] : [[text, {}]] unless text.is_a?(MarkdownText)

        runs = []
        buf = +""
        i = 0

        while i < text.length
          run, next_i = markdown_run_at(text, i)
          if run
            runs << [buf, {}] unless buf.empty?
            buf = +""
            runs << run
            i = next_i
          else
            buf << text[i]
            i += 1
          end
        end

        runs << [buf, {}] unless buf.empty?
        runs
      end

      # Checked in this order, so `**` wins over `*`.
      PAIRED_MARKERS = { "**" => :bold, "__" => :underline, "*" => :italic }.freeze

      # The formatted `[content, style]` run starting at `text[i]`, plus the
      # index just past it -- or nil when no (closed) marker starts there.
      def markdown_run_at(text, i)
        if text[i] == "[" && (close_bracket = text.index("]", i + 1)) && text[close_bracket + 1] == "(" &&
           (close_paren = text.index(")", close_bracket + 2))
          return [[text[(i + 1)...close_bracket], { link: text[(close_bracket + 2)...close_paren] }], close_paren + 1]
        end

        PAIRED_MARKERS.each do |marker, style|
          next unless text[i, marker.length] == marker && (close = text.index(marker, i + marker.length))

          return [[text[(i + marker.length)...close], { style => true }], close + marker.length]
        end
        nil
      end

      # How much taller a label is than a single line, given the space
      # between stacked lines -- 0 for a one-line label.
      def extra_height(text, line_height:)
        (lines(text).length - 1) * line_height
      end
    end
  end
end
