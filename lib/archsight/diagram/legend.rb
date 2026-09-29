# frozen_string_literal: true

require_relative "graph"
require_relative "style/relations"
require_relative "style/representers"
require_relative "style/tints"
require_relative "support/text_metrics"
require_relative "style/theme"
require_relative "legend/modes"
require_relative "legend/row"
require_relative "legend/inventory"

module Archsight
  module Diagram
    # The legend: *what* goes in it (`Inventory` and its `Row`s), and the
    # layout tree it's laid out as -- a titled `Frame` holding one `layer`
    # of `stack`s (its columns) of `Entry` leaves, sized and packed by
    # `Layout` with exactly the same machinery as the diagram itself, then
    # placed beside it (see `Layout#place_legend`).
    module Legend
      # Deliberately not part of `Theme` (see `Theme::LEGEND_FONT_SIZE`):
      # the legend reads the same under every theme.
      PADDING = 16.0
      TITLE_HEIGHT = 20.0
      ROW_HEIGHT = 22.0
      ICON_WIDTH = 30.0
      # Between an entry's icon and its label.
      LABEL_GAP = 8.0
      COLUMN_GAP = 20.0
      # Between the diagram and the legend -- room for a line looping round
      # the diagram on an outer lane (see `EdgeRouter::BridgePath`).
      GAP = 40.0
      TITLE = "Legend"

      # The prefix of every legend node's layout id -- the same reserved
      # `__asd_` namespace the parser's anonymous `__asd_anon_N` ids use.
      ID_PREFIX = "__asd_legend"

      # The titled box around the columns -- a plain container as far as
      # `Layout` is concerned, with the legend's own fixed padding/title
      # instead of the theme's.
      class Frame < Graph::Node
        def layout_padding(_theme) = PADDING
        def layout_title_height(_theme) = TITLE_HEIGHT
      end

      # One row: its `Row`'s icon then its label. Stretchable (a plain
      # rectangle, as far as `Expander` is concerned), so every entry in a
      # column widens to the column's own widest -- which is what lines
      # their icons and labels up at the column's left edge.
      class Entry < Graph::Node
        attr_accessor :row

        def leaf? = true
        def default_shape = "rectangle"
        def legend_entry? = true

        def layout_size
          width = ICON_WIDTH + LABEL_GAP + TextMetrics.rendered_width(row.label, font_size: Theme::LEGEND_FONT_SIZE)
          [width, ROW_HEIGHT + TextMetrics.extra_height(row.label, line_height: Theme::LEGEND_FONT_SIZE * 1.3)]
        end
      end

      # The rows of a legend for `graph`, drawing `relation_filter`'s
      # relations -- empty when there's nothing worth explaining (see
      # `Inventory`).
      def self.rows(graph, relation_filter:)
        relations = graph.edges.map(&:relation).uniq.select { |r| relation_filter.include?(r) }
        Inventory.new(graph, relations: relations).rows
      end

      # A `Frame` laying `rows` out in `columns` columns, filled top to
      # bottom then left to right (`ceil(rows / columns)` per column).
      def self.tree(rows, columns:)
        frame = Frame.new(id: ID_PREFIX, kind: :legend, attrs: { "label" => TITLE }, children: [], parent: nil, anonymous: false)
        layer = Graph::Layer.new(id: "#{ID_PREFIX}_columns", kind: :layer, attrs: { "gap" => COLUMN_GAP.to_s }, children: [],
                                 parent: frame, anonymous: true)
        frame.children << layer

        per_column = (rows.length / columns.to_f).ceil
        rows.each_slice(per_column).with_index do |column_rows, c|
          # `extend "height"`: every column's box as tall as the tallest, so
          # a shorter one stays top-aligned instead of centered.
          stack = Graph::Stack.new(id: "#{ID_PREFIX}_column#{c}", kind: :stack, attrs: { "gap" => "0", "extend" => "height" },
                                   children: [], parent: layer, anonymous: true)
          layer.children << stack
          column_rows.each_with_index do |row, r|
            entry = Entry.new(id: "#{ID_PREFIX}_entry#{c}_#{r}", kind: :legend_entry, attrs: { "label" => row.label }, children: [],
                              parent: stack, anonymous: false)
            entry.row = row
            stack.children << entry
          end
        end
        frame
      end

      # What `Layout` hands the renderer: where it put the legend (`frame`,
      # the root of the tree above) and on which `side` of the diagram.
      Placement = Struct.new(:frame, :side, keyword_init: true) do
        def entries = frame.children.first.children.flat_map(&:children)
        def nodes = [frame, *frame.children, *frame.children.first.children, *entries]
      end
    end
  end
end
