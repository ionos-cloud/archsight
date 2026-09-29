# frozen_string_literal: true

module Archsight
  module Diagram
    # Every spacing/sizing/font-size value the layout and renderer use, in
    # one place, so a diagram can pick a denser set for larger graphs:
    # `default` > `cozy` > `compact`. Selected per diagram with a top-level
    # `theme "cozy"` statement, or overridden from outside
    # (`render(theme:)`, `--theme`).
    #
    # Legend spacing and edge-routing margins aren't themed -- they stay
    # fixed regardless of the diagram's own density.
    Theme = Data.define(
      :name,
      # Container geometry: inner padding, and the band reserved for a
      # (non-anonymous) container's title above its children.
      :padding, :title_height,
      # Empty space around the whole diagram. Never below
      # `EdgeRouter::BridgePath::BRIDGE_MARGIN` (not themed): an edge that
      # detours around the outermost boxes runs that far outside them, and
      # would otherwise be clipped at the canvas edge.
      :canvas_margin,
      # Leaf node sizing: a node is at least `node_min_width` wide, or its
      # longest label line plus `node_label_padding`. The line is measured
      # with real Helvetica glyph widths when `measure_text_with_font_metrics`
      # is set (see `TextMetrics.rendered_width`), else estimated at a flat
      # `char_width` per char. `label_line_height` is the extra height per
      # label line beyond the first.
      :node_min_width, :node_height, :char_width, :measure_text_with_font_metrics, :node_label_padding,
      :label_line_height,
      # An actor's figure band and label band below it, and its minimum width.
      :actor_min_width, :actor_figure_height, :actor_label_height,
      # Gap between unrelated siblings, and the tight gap between a stack's ranks.
      :sibling_gap, :stack_gap,
      # Edge-label width estimate, used to widen a gap so a label fits in it.
      :edge_label_char_width, :edge_label_gap_padding,
      # Font sizes, in px.
      :node_font_size, :actor_font_size, :group_title_font_size, :boundary_title_font_size,
      :edge_label_font_size,
      # Where a container's title sits: inset from its left edge, and its
      # baseline below its top edge.
      :title_inset_x, :group_title_baseline, :boundary_title_baseline
    )

    class Theme
      # The legend's own font size -- the legend isn't themed, but its
      # `.asd-fs-*` class still has to be emitted alongside the theme's.
      LEGEND_FONT_SIZE = 12

      # A labeled edge between two ranks needs room for both the arrow and
      # the label.
      def rank_edge_label_gap = sibling_gap * 2

      # Every font size this theme renders text at, for `Stylesheet` to
      # emit one `.asd-fs-N` rule each.
      def font_sizes
        [node_font_size, actor_font_size, group_title_font_size, boundary_title_font_size,
         edge_label_font_size, LEGEND_FONT_SIZE].uniq.sort
      end

      def self.names = THEMES.keys

      def self.fetch(name)
        THEMES.fetch(name.to_s) do
          raise ArgumentError, "unknown theme #{name.to_s.inspect}; expected one of #{names.join(", ")}"
        end
      end

      DEFAULT = new(
        name: "default",
        padding: 30.0, title_height: 28.0,
        canvas_margin: 20.0,
        node_min_width: 120.0, node_height: 60.0, char_width: 8.0, measure_text_with_font_metrics: false,
        node_label_padding: 40.0, label_line_height: 16.0,
        actor_min_width: 60.0, actor_figure_height: 44.0, actor_label_height: 18.0,
        sibling_gap: 24.0, stack_gap: 6.0,
        edge_label_char_width: 6.5, edge_label_gap_padding: 16.0,
        node_font_size: 13, actor_font_size: 12, group_title_font_size: 13, boundary_title_font_size: 15,
        edge_label_font_size: 11,
        title_inset_x: 10.0, group_title_baseline: 18.0, boundary_title_baseline: 20.0
      )

      # Halfway between `default` and `compact`: noticeably tighter
      # spacing and 1px smaller fonts, with boxes sized from real glyph
      # widths like `compact`'s, for mid-sized diagrams.
      COZY = new(
        name: "cozy",
        padding: 16.0, title_height: 24.0,
        canvas_margin: 20.0,
        node_min_width: 90.0, node_height: 52.0, char_width: 7.2, measure_text_with_font_metrics: true,
        node_label_padding: 28.0, label_line_height: 15.0,
        actor_min_width: 54.0, actor_figure_height: 38.0, actor_label_height: 16.0,
        sibling_gap: 16.0, stack_gap: 5.0,
        edge_label_char_width: 6.5, edge_label_gap_padding: 13.0,
        node_font_size: 12, actor_font_size: 11, group_title_font_size: 12, boundary_title_font_size: 14,
        edge_label_font_size: 11,
        title_inset_x: 8.0, group_title_baseline: 16.0, boundary_title_baseline: 17.0
      )

      # Tighter spacing and ~2px smaller fonts, for large graphs. Node
      # widths come from real glyph widths, so boxes hug their labels.
      COMPACT = new(
        name: "compact",
        padding: 6.0, title_height: 20.0,
        canvas_margin: 20.0,
        node_min_width: 60.0, node_height: 44.0, char_width: 6.3, measure_text_with_font_metrics: true,
        node_label_padding: 16.0, label_line_height: 14.0,
        actor_min_width: 48.0, actor_figure_height: 32.0, actor_label_height: 14.0,
        sibling_gap: 8.0, stack_gap: 4.0,
        edge_label_char_width: 5.9, edge_label_gap_padding: 10.0,
        node_font_size: 11, actor_font_size: 10, group_title_font_size: 11, boundary_title_font_size: 13,
        edge_label_font_size: 10,
        title_inset_x: 6.0, group_title_baseline: 14.0, boundary_title_baseline: 15.0
      )

      THEMES = [DEFAULT, COZY, COMPACT].to_h { |t| [t.name, t] }.freeze
    end
  end
end
