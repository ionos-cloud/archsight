# frozen_string_literal: true

require_relative "typst"
require_relative "markdown"
require_relative "../view_table"
require_relative "../export/confluence/tables"

module Archsight
  module Pdf
    # A ViewTable::Table (the result of a view, of requirements or of an analysis) as a Typst table. Views are live
    # in Archsight; in the PDF they are the data of the moment of the export.
    module Tables
      # A column whose longest text is longer than this shares the width (`fr`), shorter ones take what they need
      LONG = 30
      SMALL_FONT_FROM = 4 # columns
      Confluence = Export::Confluence::Tables

      module_function

      # @param table [Archsight::ViewTable::Table]
      # @param markdown [#call] Typst markup of a markdown text, for the cells of `as: :markdown`
      # @param empty [String] shown instead of the table when there are no rows
      # @return [String] Typst markup
      def typst(table, markdown:, empty: "No results")
        parts = []
        parts << heading(table) unless table.title.to_s.empty?
        parts << (table.rows.empty? ? Typst.note(empty, fill: "#f2f2f2") : grid(table, markdown))
        parts << "#emph[#{Typst.str("#{table.cut} more #{table.cut == 1 ? "row" : "rows"} not shown, see Archsight")}]" if table.cut.positive?
        parts.join("\n\n")
      end

      def heading(table)
        count = "(#{table.total} #{table.total == 1 ? "item" : "items"})"
        "#block(sticky: true)[#strong[#{Typst.str(table.title)}] #text(fill: luma(120))[#{Typst.str(count)}]]"
      end

      def grid(table, markdown)
        head = table.columns.map { |c| "[#text(weight: \"semibold\")[#{Typst.str(c)}]]" }
        cells = table.rows.flat_map { |row| row.map { |cell| "[#{cell(cell, markdown)}]" } }
        out = "#table(columns: (#{widths(table).join(", ")},), table.header(#{head.join(", ")}), #{cells.join(", ")})"
        table.columns.size >= SMALL_FONT_FROM ? "#[#set text(size: 8.5pt)\n#{out}]" : out
      end

      # `auto` for short columns, a share of the rest for long ones, so wide tables wrap instead of running off the page
      def widths(table)
        table.columns.each_index.map do |i|
          longest = [table.columns[i].length, *table.rows.map { |row| row[i] ? text_of(row[i]).length : 0 }].max
          longest > LONG ? "#{(longest / LONG.to_f).round.clamp(1, 4)}fr" : "auto"
        end
      end

      def text_of(cell)
        cell.resources.empty? ? cell.text.to_s : cell.resources.map(&:name).join(" ")
      end

      def cell(cell, markdown)
        return cell.resources.map { |resource| Typst.str(resource.name) }.join("#linebreak()") unless cell.resources.empty?

        case cell.as
        when :status then badge(cell.text, Confluence::STATUS_COLOURS)
        when :priority then cell.text.to_s.empty? ? "" : badge(cell.text, Confluence::PRIORITY_COLOURS)
        when :markdown then markdown.call(cell.text.to_s)
        else cell.text.to_s.split("\n").map { |line| Typst.str(line) }.join("#linebreak()")
        end
      end

      def badge(text, colours)
        Typst.badge(text, Markdown::STATUS_FILL.fetch(colours.fetch(text, "grey"), "#e8e8e8"))
      end
    end
  end
end
