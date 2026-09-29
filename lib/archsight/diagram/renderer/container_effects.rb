# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # A container's own fill gradient, plus a `boundary`'s own drop-shadow
      # on top of that -- `<linearGradient>`/`<filter>` defs, mirroring
      # `MarkerDefs`'s "only-what's-used, id-keyed" shape: one gradient per
      # distinct `(tint, tint_depth)` pair actually used by any *named*
      # `group`/`boundary`/`layer`/`stack` in *this* diagram (an anonymous
      # `layer`/`stack` never renders a box at all -- see
      # `NodeRenderer#render`'s `anonymous?` branch -- so it has no fill to
      # generate a gradient for), plus one shared shadow filter if any
      # `boundary` exists at all (tinted or not) -- the shadow stays
      # boundary-only, marking it out as a heavier/more significant box than
      # a plain group/layer/stack, while every container shares the same
      # subtle "elevated surface" gradient. `defs_markup` is unwrapped (no
      # `<defs>` of its own) -- `Renderer#render` combines it with
      # `MarkerDefs`'s own unwrapped markers into one shared `<defs>`,
      # rather than a second one alongside it.
      class ContainerEffects
        SHADOW_FILTER_ID = "asd-boundary-shadow"

        def initialize(graph)
          @graph = graph
        end

        def self.gradient_id(tint_name, level) = "asd-container-gradient-#{tint_name}-#{level.clamp(0, Tint::MAX_SHADE_LEVEL)}"
        def self.shadow_filter_id = SHADOW_FILTER_ID

        def defs_markup
          m = Markup.new
          used_container_tints.each { |tint_name, level| gradient(m, tint_name, level) }
          shadow_filter(m) if any_boundary?
          m.to_s
        end

        private

        def any_boundary?
          @graph.nodes_by_id.values.any?(&:boundary?)
        end

        # `tint_depth` is unbounded but a color at any level beyond
        # `MAX_SHADE_LEVEL` is already identical to `MAX_SHADE_LEVEL`'s own
        # (`Tint#fill`/`#darken` clamp it) -- clamped here too so the id this
        # generates always matches `self.class.gradient_id`'s own clamp, and
        # two containers nested past that depth share one gradient def
        # instead of generating a redundant identical one each.
        def used_container_tints
          @graph.nodes_by_id.values.select { |n| n.container? && !n.anonymous? }
                                   .map { |n| [n.effective_tint, n.tint_depth.clamp(0, Tint::MAX_SHADE_LEVEL)] }
                                   .uniq
        end

        # Top-to-bottom, from this tint/level's own base color to one shade
        # deeper -- reusing the same darkening ramp nested same-tint boxes
        # already use (`Tint#fill`), rather than inventing a separate "a bit
        # darker" amount just for this gradient's second stop.
        def gradient(m, tint_name, level)
          tint = Tints.for(tint_name)
          m.element("linearGradient", id: self.class.gradient_id(tint_name, level), x1: "0%", y1: "0%", x2: "0%", y2: "100%") do
            m.element("stop", offset: "0%", "stop-color": tint.fill(level))
            m.element("stop", offset: "100%", "stop-color": tint.fill(level + 1))
          end
        end

        # The classic blur/offset/opacity/merge drop-shadow recipe, not the
        # `feDropShadow` shorthand -- the same "don't assume a newer SVG/CSS
        # feature is universally supported" lesson that moved `rx` back to a
        # plain attribute (see `Representers::Rectangle`/`NodeRenderer`):
        # this recipe is the one with the longest, most consistent
        # cross-renderer support. A low, fixed opacity (`slope="0.25"`) and
        # small blur/offset keep it "very light," not a heavy drop-shadow.
        def shadow_filter(m)
          m.element("filter", id: SHADOW_FILTER_ID, x: "-20%", y: "-20%", width: "140%", height: "140%") do
            m.element("feGaussianBlur", in: "SourceAlpha", stdDeviation: 3, result: "blur")
            m.element("feOffset", in: "blur", dx: 0, dy: 2, result: "offsetBlur")
            m.element("feComponentTransfer", in: "offsetBlur", result: "shadow") do
              m.element("feFuncA", type: "linear", slope: "0.25")
            end
            m.element("feMerge") do
              m.element("feMergeNode", in: "shadow")
              m.element("feMergeNode", in: "SourceGraphic")
            end
          end
        end
      end
    end
  end
end
