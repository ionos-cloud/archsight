# frozen_string_literal: true

require_relative "../native"

module Archsight
  module Diagram
    # Boxes a route between two nodes should avoid drawing through: every
    # other node's box, except ones on either endpoint's own ancestor chain
    # -- the containers it's already inside, which a route between its own
    # contents is expected to freely cross (its padding is exactly the room
    # reserved for that). A sibling container or an unrelated leaf is fair
    # game to route around. Shared by both routing stages (`EdgeRouting`,
    # `DataflowRouting`), which otherwise had the same four lines each.
    class ObstacleMap
      # `excluding`'s result: the obstacle boxes themselves, in map order,
      # plus -- when the native kernels are built -- the whole map's
      # prepacked box table (`Native.pack_boxes`, packed once per map) and
      # the indices of the boxes this list leaves out, so a kernel call can
      # reuse the table instead of repacking every box for every edge.
      # Frozen, so the list can never drift from the table it's paired with.
      class Obstacles < Array
        attr_reader :native_table, :native_excluded

        def initialize(boxes, native_table = nil, native_excluded = nil)
          super(boxes)
          @native_table = native_table
          @native_excluded = native_excluded
          freeze
        end
      end

      # `ignoring` ids are never obstacles: boxes that aren't drawn (the
      # anonymous stack/layer wrappers a diagram groups its nodes with), so
      # a line clipping one crosses nothing visible.
      def initialize(boxes, ignoring: [])
        @boxes = boxes
        @ignored = ignoring.to_a
        return unless Native.available?

        @index = boxes.keys.each_with_index.to_h
        @native_table = Native.pack_boxes(boxes.values)
      end

      def excluding(from, to)
        skip = from.ancestor_ids | to.ancestor_ids | @ignored
        obstacles = @boxes.except(*skip).values
        return Obstacles.new(obstacles) unless @native_table

        Obstacles.new(obstacles, @native_table, skip.filter_map { |id| @index[id] }.pack("l*"))
      end
    end
  end
end
