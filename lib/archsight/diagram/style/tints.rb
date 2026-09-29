# frozen_string_literal: true

module Archsight
  module Diagram
    # One small object per named "tint" -- a pastel fill + matching stronger
    # border color pair a component/group/boundary can opt into via the
    # `tint` attr (see `Graph::Node#tint`/`#effective_tint`), mirroring
    # `Relations`/`Representers`'s own name-keyed registry pattern.
    #
    # `fill(level)`/`border(level)` darken the base pair for nested same-tint
    # containers (see `Graph::Node#tint_depth`) -- a plain percentage scale
    # of each RGB channel toward black, clamped at `MAX_SHADE_LEVEL` so even
    # deeply nested boxes stay a legible color rather than approaching black.
    class Tint
      SHADE_STEP = 0.04
      MAX_SHADE_LEVEL = 4

      attr_reader :name

      def initialize(name:, fill:, border:)
        @name = name
        @fill = fill
        @border = border
      end

      def fill(level = 0) = self.class.darken(@fill, level)
      def border(level = 0) = self.class.darken(@border, level)

      # The CSS class names `fill(level)`/`border(level)`'s colors are
      # published under (see `Renderer::Stylesheet`, which generates one
      # rule per `(name, 0..MAX_SHADE_LEVEL)` pair for every registered
      # tint) -- the single source of truth both a color's *consumer*
      # (`NodeRenderer`, `Legend::Row`) and its *generator* (`Stylesheet`)
      # call through, so a class can never be referenced without being
      # defined. Clamped exactly like the color methods themselves.
      def fill_class(level = 0) = "asd-fill-#{name}-#{level.clamp(0, self.class::MAX_SHADE_LEVEL)}"
      def border_class(level = 0) = "asd-stroke-#{name}-#{level.clamp(0, self.class::MAX_SHADE_LEVEL)}"

      def self.darken(hex, level)
        factor = 1.0 - (level.clamp(0, MAX_SHADE_LEVEL) * SHADE_STEP)
        channels = [hex[1..2], hex[3..4], hex[5..6]].map { |c| (c.to_i(16) * factor).round.clamp(0, 255) }
        format("#%02x%02x%02x", *channels)
      end
    end

    module Tints
      REGISTRY = {} # rubocop:disable Style/MutableConstant -- filled by .register

      def self.register(name, tint) = REGISTRY[name] = tint
      def self.for(name) = REGISTRY.fetch(name) { REGISTRY.fetch("gray") }
      def self.names = REGISTRY.keys

      register("gray", Tint.new(name: "gray", fill: "#fbfcfd", border: "#9ca3af"))
      register("blue", Tint.new(name: "blue", fill: "#eff6ff", border: "#2563eb"))
      register("indigo", Tint.new(name: "indigo", fill: "#eef2ff", border: "#4f46e5"))
      register("purple", Tint.new(name: "purple", fill: "#faf5ff", border: "#9333ea"))
      register("pink", Tint.new(name: "pink", fill: "#fdf2f8", border: "#db2777"))
      register("red", Tint.new(name: "red", fill: "#fef2f2", border: "#dc2626"))
      register("orange", Tint.new(name: "orange", fill: "#fff7ed", border: "#ea580c"))
      register("yellow", Tint.new(name: "yellow", fill: "#fefce8", border: "#ca8a04"))
      register("green", Tint.new(name: "green", fill: "#f0fdf4", border: "#16a34a"))
      register("teal", Tint.new(name: "teal", fill: "#f0fdfa", border: "#0d9488"))
      register("cyan", Tint.new(name: "cyan", fill: "#ecfeff", border: "#0891b2"))
      register("brown", Tint.new(name: "brown", fill: "#f7f1e8", border: "#92703a"))
    end
  end
end
