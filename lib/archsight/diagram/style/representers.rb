# frozen_string_literal: true

require_relative "../renderer/svg_format"
require_relative "../renderer/markup"

module Archsight
  module Diagram
    # One small class per leaf `shape` (not `kind` -- any leaf can override
    # its shape via the `shape` attr, so this stays a separate hierarchy
    # looked up by name rather than baked into `Graph::Node`'s own class).
    # Each `Representer` knows how to draw itself (`markup`), where its own
    # figure sits within the node's box (`figure_geometry`, identity for
    # every shape but `actor`, whose figure occupies a band above its label
    # instead of the whole box), where its label sits and at what size
    # (`label_x`/`label_y`/`label_font_size`), whether it can be stretched
    # to fill extra space (`stretchable?`, consulted by `Layout::Expander`),
    # whether its outline is an ellipse for edge-anchor purposes
    # (`elliptical?`, consulted by `EdgeRouter`), and its legend label
    # (`legend_label`).
    #
    # `markup` takes its coloring as three separate CSS class names (a
    # fill/stroke/stroke-width color scheme selected by the caller -- see
    # `Renderer::Stylesheet` for where those classes are actually defined)
    # rather than raw hex/width values, and rather than one merged class
    # string -- kept separate so a shape with a `fill: none` secondary
    # element (a cylinder/pipe's back arc, a file's crease) can drop just
    # `fill_class` for that one element without any CSS specificity/ordering
    # trick to make a `fill: none` rule reliably beat a fill-color rule of
    # equal specificity. Returns a self-contained markup string, built via a
    # fresh `Renderer::Markup` -- the caller (`NodeRenderer#render_shape`,
    # `Legend::ShapeRow#icon`) embeds it into its own builder with `.raw`.
    module Representers
      class Base
        include SvgFormat

        # `id:` is the base id of the node (or legend row) being drawn -- each
        # primitive gets its own `<id>__<part>` id (see `Renderer::ElementIds`),
        # or none at all when `id` is `nil`.
        def markup(cx, cy, w, h, fill_class:, stroke_class:, width_class:, id: nil) = raise NotImplementedError

        # `[cx, cy, w, h]` for the shape's own drawn figure within `box` --
        # identity by default (the figure fills the whole box); `actor`
        # overrides this to a shorter band above its label.
        def figure_geometry(box, _theme) = [box.x, box.y, box.width, box.height]

        def label_x(box) = box.x
        def label_y(box, _theme) = box.y
        def label_font_size(theme) = theme.node_font_size
        def stretchable? = false
        def elliptical? = false
        def legend_label = raise NotImplementedError

        # Adjusts a rectangle-boundary anchor point that landed inside a bit
        # of this shape's box its outline doesn't actually cover (only
        # `FileRepresenter`'s chamfered corner does this) back onto the real
        # outline. `point` is what `EdgeRouter::StraightPath.anchor_point`
        # already computed for the ray `(dx, dy)` from `box`'s center; a
        # no-op by default.
        def correct_anchor_point(_box, _dx, _dy, point) = point

        private

        # A cylinder/pipe's rounded cap size, given the box's extent along
        # the cap's own axis (height for a cylinder, width for a pipe) --
        # shared since both are the same shape, just rotated 90 degrees.
        def cap(extent) = [[extent * 0.22, 12.0].min, 4.0].max

        # `fill_class`/`stroke_class`/`width_class` as the array `Markup`'s
        # `class:` attribute wants -- shared by every representer's own
        # `markup`, and by `outline_classes` below for a secondary "no fill"
        # element.
        def classes(*extra, fill_class:, stroke_class:, width_class:)
          [*extra, fill_class, stroke_class, width_class]
        end

        # The same three classes, but for a secondary path/element that has
        # no fill of its own (a cylinder/pipe's back arc, a file's crease,
        # an actor's every line/circle) -- drops `fill_class` entirely
        # instead of layering an `asd-fill-none` class on top of it,
        # since two same-specificity `fill` rules would otherwise leave the
        # actually-applied one up to CSS declaration order.
        def outline_classes(*extra, stroke_class:, width_class:)
          [*extra, "asd-fill-none", stroke_class, width_class]
        end

        def part(id, name) = id && "#{id}__#{name}"
      end

      class Rectangle < Base
        def markup(cx, cy, w, h, id: nil, **style)
          m = Renderer::Markup.new
          m.element("rect", id: part(id, "body"), x: fmt(cx - (w / 2.0)), y: fmt(cy - (h / 2.0)), width: fmt(w), height: fmt(h), rx: 6,
                            class: classes(**style))
          m.to_s
        end

        def stretchable? = true
        def legend_label = "Component"
      end

      class Circle < Base
        def markup(cx, cy, w, h, id: nil, **style)
          m = Renderer::Markup.new
          m.element("ellipse", id: part(id, "body"), cx: fmt(cx), cy: fmt(cy), rx: fmt(w / 2.0), ry: fmt(h / 2.0), class: classes(**style))
          m.to_s
        end

        def elliptical? = true
        def legend_label = "API / endpoint"
      end

      class Cylinder < Base
        # A cylinder's rounded top cap reads as taking up more visual room
        # than the flat bottom, so dead-center text looks too high; nudge it
        # down by a full cap height to sit where it visually balances.
        def label_y(box, _theme) = box.y + cap(box.height)

        def markup(cx, cy, w, h, id: nil, **style)
          left = cx - (w / 2.0)
          right = cx + (w / 2.0)
          top = cy - (h / 2.0)
          bottom = cy + (h / 2.0)
          rx = w / 2.0
          c = cap(h)

          m = Renderer::Markup.new
          m.element("path", id: part(id, "body"), d: "M #{fmt(left)} #{fmt(top + c)} A #{fmt(rx)} #{fmt(c)} 0 0 1 #{fmt(right)} #{fmt(top + c)} " \
                                                     "L #{fmt(right)} #{fmt(bottom - c)} A #{fmt(rx)} #{fmt(c)} 0 0 1 #{fmt(left)} #{fmt(bottom - c)} Z",
                            class: classes(**style))
          m.element("path", id: part(id, "cap"), d: "M #{fmt(left)} #{fmt(top + c)} A #{fmt(rx)} #{fmt(c)} 0 0 0 #{fmt(right)} #{fmt(top + c)}",
                            class: outline_classes(stroke_class: style[:stroke_class], width_class: style[:width_class]))
          m.to_s
        end

        def stretchable? = true
        def legend_label = "Datastore"
      end

      class Pipe < Base
        # A pipe is a cylinder rotated 90 degrees, so the same "the rounded
        # cap reads as taking more room" effect pushes its label off-center
        # horizontally instead of vertically -- nudge it right by a full cap
        # width to visually balance against the open left cap.
        def label_x(box) = box.x + cap(box.width)

        # A `cylinder` rotated 90 degrees: rounded caps on the left/right
        # ends instead of top/bottom, same "hollow tube" depth cue via a
        # second path drawing the back arc of one cap.
        def markup(cx, cy, w, h, id: nil, **style)
          left = cx - (w / 2.0)
          right = cx + (w / 2.0)
          top = cy - (h / 2.0)
          bottom = cy + (h / 2.0)
          ry = h / 2.0
          c = cap(w)

          m = Renderer::Markup.new
          m.element("path", id: part(id, "body"), d: "M #{fmt(left + c)} #{fmt(top)} A #{fmt(c)} #{fmt(ry)} 0 0 0 #{fmt(left + c)} #{fmt(bottom)} " \
                                                     "L #{fmt(right - c)} #{fmt(bottom)} A #{fmt(c)} #{fmt(ry)} 0 0 0 #{fmt(right - c)} #{fmt(top)} Z",
                            class: classes(**style))
          m.element("path", id: part(id, "cap"), d: "M #{fmt(left + c)} #{fmt(top)} A #{fmt(c)} #{fmt(ry)} 0 0 1 #{fmt(left + c)} #{fmt(bottom)}",
                            class: outline_classes(stroke_class: style[:stroke_class], width_class: style[:width_class]))
          m.to_s
        end

        def stretchable? = true
        def legend_label = "Queue / topic"
      end

      # An actor's figure occupies a fixed-height band at the top of its
      # box, with its label in its own band below -- a stick figure has
      # nowhere to put text "inside" it the way a rect or ellipse does.
      class Actor < Base
        def figure_geometry(box, theme)
          [box.x, box.top + (theme.actor_figure_height / 2.0), box.width, theme.actor_figure_height]
        end

        def label_y(box, theme) = box.top + theme.actor_figure_height + (theme.actor_label_height / 2.0)
        def label_font_size(theme) = theme.actor_font_size

        def markup(cx, cy, w, h, id: nil, **style)
          outline = outline_classes(stroke_class: style[:stroke_class], width_class: style[:width_class])
          head_r = [h * 0.22, 10.0].min
          top = cy - (h / 2.0)
          bottom = cy + (h / 2.0)
          head_cy = top + head_r
          body_top = head_cy + head_r
          body_bottom = bottom - (head_r * 0.4)
          arm_span = w * 0.35

          m = Renderer::Markup.new
          m.element("circle", id: part(id, "head"), cx: fmt(cx), cy: fmt(head_cy), r: fmt(head_r), class: outline)
          m.element("line", id: part(id, "torso"), x1: fmt(cx), y1: fmt(body_top), x2: fmt(cx), y2: fmt(body_bottom), class: outline)
          m.element("line", id: part(id, "arms"), x1: fmt(cx - arm_span), y1: fmt(body_top + (head_r * 0.6)), x2: fmt(cx + arm_span),
                            y2: fmt(body_top + (head_r * 0.6)), class: outline)
          m.element("line", id: part(id, "leg-l"), x1: fmt(cx), y1: fmt(body_bottom), x2: fmt(cx - arm_span), y2: fmt(bottom), class: outline)
          m.element("line", id: part(id, "leg-r"), x1: fmt(cx), y1: fmt(body_bottom), x2: fmt(cx + arm_span), y2: fmt(bottom), class: outline)
          m.to_s
        end

        def elliptical? = true
        def legend_label = "External actor"
      end

      # A page with its top-right corner folded down -- the classic
      # "file/document" icon. `fold` is clamped so it never exceeds the
      # shape's own half-width/half-height, however small a node gets.
      # Named `FileRepresenter` (not `File`) to avoid shadowing ::File.
      class FileRepresenter < Base
        # The chamfer's leg length -- capped so it never exceeds the
        # shape's own half-width/half-height, however small a node gets.
        # The single source of truth for the cut corner's size, read by
        # both `markup` (drawing it) and `correct_anchor_point` (keeping a
        # straight edge's endpoint off the bit of the box it cuts away).
        FOLD = 14.0

        def markup(cx, cy, w, h, id: nil, **style)
          left = cx - (w / 2.0)
          right = cx + (w / 2.0)
          top = cy - (h / 2.0)
          bottom = cy + (h / 2.0)
          fold = fold_size(w, h)

          m = Renderer::Markup.new
          m.element("path", id: part(id, "body"), d: "M #{fmt(left)} #{fmt(top)} L #{fmt(right - fold)} #{fmt(top)} " \
                                                     "L #{fmt(right)} #{fmt(top + fold)} L #{fmt(right)} #{fmt(bottom)} L #{fmt(left)} #{fmt(bottom)} Z",
                            class: classes("asd-shape-file", **style))
          m.element("path", id: part(id, "fold"), d: "M #{fmt(right - fold)} #{fmt(top)} L #{fmt(right - fold)} #{fmt(top + fold)} L #{fmt(right)} #{fmt(top + fold)}",
                            class: outline_classes("asd-shape-file", stroke_class: style[:stroke_class], width_class: style[:width_class]))
          m.to_s
        end

        def stretchable? = true
        def legend_label = "File / document"

        # If the plain-rectangle anchor point fell inside the chamfered
        # triangle (the bit of the box the fold actually cuts away), slide
        # it back onto the chamfer's own diagonal edge instead -- the line
        # from `(right - fold, top)` to `(right, top + fold)`, i.e. every
        # point on it satisfies `x - y == (right - fold) - top`. Re-solving
        # the same center-to-target ray (`x, y = box.x + t*dx, box.y +
        # t*dy`) for that line's `t` finds exactly where it crosses.
        def correct_anchor_point(box, dx, dy, point)
          px, py = point
          fold = fold_size(box.width, box.height)
          right = box.x + (box.width / 2.0)
          top = box.y - (box.height / 2.0)
          return point unless px > right - fold && py < top + fold

          denom = dx - dy
          return point if denom.zero?

          t = ((right - fold - top) - (box.x - box.y)) / denom
          [box.x + (dx * t), box.y + (dy * t)]
        end

        private

        def fold_size(w, h) = [w / 2.0, h / 2.0, FOLD].min
      end

      # Sharp corners (unlike the default rectangle's rx="6") -- reads as a
      # plain slab, matching how a middleware/pipeline layer packed
      # edge-to-edge into a "no-gap" stack with its neighbors should look:
      # one continuous block, not a row of separately rounded pills. Named
      # `ModuleRepresenter` (not `Module`) to avoid shadowing ::Module.
      class ModuleRepresenter < Base
        def markup(cx, cy, w, h, id: nil, **style)
          m = Renderer::Markup.new
          m.element("rect", id: part(id, "body"), x: fmt(cx - (w / 2.0)), y: fmt(cy - (h / 2.0)), width: fmt(w), height: fmt(h), class: classes(**style))
          m.to_s
        end

        def stretchable? = true
        def legend_label = "Module"
      end

      REGISTRY = {} # rubocop:disable Style/MutableConstant -- filled by .register

      def self.register(name, representer)
        REGISTRY[name] = representer
      end

      def self.for(name)
        REGISTRY.fetch(name) { REGISTRY.fetch("rectangle") }
      end

      def self.names = REGISTRY.keys

      register("rectangle", Rectangle.new)
      register("circle", Circle.new)
      register("cylinder", Cylinder.new)
      register("pipe", Pipe.new)
      register("actor", Actor.new)
      register("file", FileRepresenter.new)
      register("module", ModuleRepresenter.new)
    end
  end
end
