# frozen_string_literal: true

module Archsight
  module Diagram
    module Legend
      # One legend row's identity: its own icon markup and label, and how
      # it behaves once assembled into the legend (`deferred?`/`wrap`) --
      # replaces the previous untyped `{ kind:, key:, label:, ... }` Hash
      # that `Legend` switched on twice (once to build its icon, once to
      # decide whether/how to wrap it).
      class Row
        attr_reader :label

        def initialize(label)
          @label = label
        end

        # Whether this row's label paints on the deferred `@texts` layer
        # with everything else (see `TextRenderer#halo_text`), or inline
        # right here -- only a dataflow row needs the latter, so a
        # generated `:has()` hover rule (see `MarkerDefs`) can target it
        # by its document position.
        def deferred? = true

        # The row's own id, minus the legend's `asd-legend-` prefix (see
        # `Renderer::LegendRenderer#render`, which also de-duplicates them).
        def id_key = raise NotImplementedError

        # Wraps a row's own already-built icon+label markup in its own
        # `<g id>` -- a dataflow row's also carries what its
        # hover rule targets.
        def wrap(markup, id:)
          m = Renderer::Markup.new
          m.element("g", id: id) { m.raw(markup) }
          m.to_s
        end

        protected

        # Shared by RelationRow/DataflowRow -- a short horizontal sample
        # line styled like the relation/dataflow it represents. `css_class`
        # is whatever `Markup`'s own `class:` attribute accepts (a String
        # or an Array with `nil`s to drop).
        def legend_line_sample(cx, cy, css_class:, marker_id:, id:)
          x1 = cx - (ICON_WIDTH / 2.0) + 3
          x2 = cx + (ICON_WIDTH / 2.0) - 3
          m = Renderer::Markup.new
          m.element("line", id: id, x1: SvgFormat.fmt(x1), y1: SvgFormat.fmt(cy), x2: SvgFormat.fmt(x2), y2: SvgFormat.fmt(cy),
                            class: ["asd-line", css_class], "marker-end": "url(##{marker_id})")
          m.to_s
        end
      end

      class ShapeRow < Row
        def initialize(label, shape:, tint:, width_class: "asd-stroke-thin")
          super(label)
          @shape = shape
          @tint = tint
          @width_class = width_class
        end

        def id_key = "shape-#{Renderer::ElementIds.slug(label)}"

        def icon(cx, cy, id:)
          Representers.for(@shape).markup(cx, cy, ICON_WIDTH - 6, ROW_HEIGHT - 8, id: "#{id}__icon",
                                                                                  fill_class: @tint.fill_class, stroke_class: @tint.border_class,
                                                                                  width_class: @width_class)
        end
      end

      class RelationRow < Row
        def initialize(label, relation:)
          super(label)
          @relation = relation
        end

        def id_key = "relation-#{Renderer::ElementIds.slug(@relation)}"

        def icon(cx, cy, id:)
          legend_line_sample(cx, cy, css_class: ["asd-relation-#{@relation}", "asd-stroke-thin"],
                                     marker_id: Renderer::MarkerDefs.marker_id(@relation), id: "#{id}__icon")
        end
      end

      class DataflowRow < Row
        attr_reader :key

        def initialize(label, dataflow:)
          super(label)
          @dataflow = dataflow
          @key = dataflow.id
        end

        def id_key = "dataflow-#{Renderer::ElementIds.slug(@key)}"

        def icon(cx, cy, id:)
          legend_line_sample(cx, cy, css_class: ["asd-relation-data", "asd-dataflow-line",
                                                 (Renderer::MarkerDefs.color_class(@dataflow.color) if @dataflow.color)],
                                     marker_id: Renderer::MarkerDefs.marker_id("data", color: @dataflow.color), id: "#{id}__icon")
        end

        def deferred? = false

        # Wrapped (and drawn inline instead of deferred, see `deferred?`)
        # so a hover rule generated in `MarkerDefs` can target this exact
        # row via `:has()` and animate the matching `data-dataflow`
        # line(s) in the diagram, wherever they are in the document.
        def wrap(markup, id:)
          m = Renderer::Markup.new
          m.element("g", id: id, class: "asd-legend-dataflow", "data-dataflow": @key) { m.raw(markup) }
          m.to_s
        end
      end

      # A tint-colored swatch row, shaped like the box it stands for:
      # `dash_class: nil` for a plain leaf's solid fill, `"asd-swatch-boundary"`/
      # `"asd-swatch-container"` for a boundary/group-shaped dashed one
      # -- see `NodeRenderer#render_container`, which those two dash
      # patterns mirror. Covers three cases (see `Legend::Inventory`):
      # the single generic "Trust boundary" row (untinted boundaries),
      # one row per *explicitly* tinted boundary/group/layer/stack (named
      # after its own label, so the color is tied to a specific box), and
      # one flat row per tint used only on a leaf (which has no name of
      # its own to borrow, so it's just labeled by the tint).
      class SwatchRow < Row
        def initialize(label, tint:, dash_class: nil)
          super(label)
          @tint = tint
          @dash_class = dash_class
        end

        def id_key = "swatch-#{Renderer::ElementIds.slug(label)}"

        def icon(cx, cy, id:)
          m = Renderer::Markup.new
          m.element("rect", id: "#{id}__icon", x: SvgFormat.fmt(cx - (ICON_WIDTH / 2.0) + 3), y: SvgFormat.fmt(cy - 6), width: SvgFormat.fmt(ICON_WIDTH - 6),
                            height: 12, rx: 3, class: ["asd-swatch", @dash_class, @tint.fill_class, @tint.border_class])
          m.to_s
        end
      end
    end
  end
end
