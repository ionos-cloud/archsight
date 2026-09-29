# frozen_string_literal: true

module Archsight
  module Diagram
    # A layout axis (width/x, or height/y) -- abstracts reading/writing a
    # Box's size and position along that axis, so callers don't need to
    # hand-write `axis == :width ? box.foo : box.bar` at every call site.
    class Axis
      def initialize(width)
        @width = width
      end

      def size(box) = @width ? box.width : box.height
      def set_size(box, value) = @width ? (box.width = value) : (box.height = value)
      def position(box) = @width ? box.x : box.y
      def set_position(box, value) = @width ? (box.x = value) : (box.y = value)
      def leading_edge(box) = @width ? box.left : box.top
      def trailing_edge(box) = @width ? box.right : box.bottom

      # This axis's index into a plain `[x, y]`-shaped pair (not a `Box`) --
      # e.g. a raw force vector, where there's no `Box` to call `position`
      # on.
      def index = @width ? 0 : 1

      # The other axis -- e.g. a `stack`'s main axis (height, the direction
      # it packs children in) has width as its cross axis.
      def cross = @width ? HEIGHT : WIDTH

      def to_s = @width ? "width" : "height"

      WIDTH = new(true)
      HEIGHT = new(false)
    end
  end
end
