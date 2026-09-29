# frozen_string_literal: true

require_relative "../legend"

module Archsight
  module Diagram
    class Renderer
      # Legend markup, drawn wherever `Layout` placed it (see `Legend` and
      # `Layout#place_legend`): its frame and title, then each entry's icon
      # and label at that entry's own box. Deciding *which* rows belong
      # here at all lives in `Legend::Inventory`, and *where* each one sits
      # in `Layout`; this class only draws them.
      class LegendRenderer
        include SvgFormat

        LEGEND_ID = "asd-legend"

        def initialize(text_renderer:)
          @text_renderer = text_renderer
        end

        # `placement` is a `Layout::Result#legend`; `boxes` the layout's own.
        def render(placement, boxes)
          frame = boxes[placement.frame.id]
          entries = placement.entries
          svg = Markup.new
          svg.element("g", id: LEGEND_ID, "data-asd-kind": "legend", "data-asd-side": placement.side) do
            svg.element("rect", id: "#{LEGEND_ID}__bg", x: fmt(frame.left), y: fmt(frame.top), width: fmt(frame.width), height: fmt(frame.height),
                                class: ["asd-legend-bg", Tints.for("gray").border_class])
            svg.raw(@text_renderer.halo_text(frame.left + Legend::PADDING, frame.top + Legend::PADDING + 4, Legend::TITLE,
                                             font_size: Theme::LEGEND_FONT_SIZE, weight: "bold", anchor: "start",
                                             attrs: { id: "#{LEGEND_ID}__title", "data-asd-owner": LEGEND_ID }))

            row_ids = ElementIds.unique_tokens(entries.map { |e| e.row.id_key }).map { |key| "#{LEGEND_ID}-#{key}" }
            entries.zip(row_ids) { |entry, row_id| svg.raw(entry_markup(entry.row, boxes[entry.id], row_id)) }
          end
          svg.to_s
        end

        private

        # A row's icon, centered in the entry's leading `ICON_WIDTH`, then
        # its label -- both on the entry's own vertical center.
        def entry_markup(row, box, row_id)
          icon = row.icon(box.left + (Legend::ICON_WIDTH / 2.0), box.y, id: row_id)
          label = @text_renderer.halo_text(box.left + Legend::ICON_WIDTH + Legend::LABEL_GAP, box.y, row.label,
                                           font_size: Theme::LEGEND_FONT_SIZE, anchor: "start", baseline: "central",
                                           defer: row.deferred?, attrs: { id: "#{row_id}__label", "data-asd-owner": row_id })
          row.wrap(icon + label, id: row_id)
        end
      end
    end
  end
end
