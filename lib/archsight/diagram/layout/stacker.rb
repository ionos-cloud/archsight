# frozen_string_literal: true

require_relative "../support/axis"

module Archsight
  module Diagram
    class Layout
      # Deterministic linear packing along an axis — no physics, just
      # declaration order plus a gap policy. Used for both `stack`
      # (Axis::HEIGHT) and `layer` (Axis::WIDTH); the only real difference
      # between them is the axis and the default gap.
      class Stacker
        def initialize(boxes)
          @boxes = boxes
        end

        # Packs `children` in declaration order along `axis`, and centers
        # all of them on a shared centerline along the *cross* axis (the
        # size used for that centerline is the largest cross-axis size
        # among `children`), so mixed sizes still align visually instead of
        # just being top/left-justified.
        #
        # `label_gaps` (unordered [id, id] pair => minimum gap) and
        # `related_pairs` (array of unordered [id, id] pairs) are precomputed
        # by the caller from the graph's edges — this class has no knowledge
        # of the graph, only of the boxes it's arranging. For each adjacent
        # pair the regular gap is `related_gap` if the pair is in
        # `related_pairs`, otherwise `default_gap`; a label gap is only a
        # minimum on top of that (room for the label), so it can widen the
        # gap but never shrink a larger one -- e.g. an explicit `gap "150"`.
        def pack(children, axis:, default_gap:, related_gap:, label_gaps: {}, related_pairs: [])
          return if children.empty?

          cross = axis.cross
          centerline = children.map { |c| cross.size(@boxes[c.id]) }.max / 2.0

          pos = 0.0
          children.each_with_index do |c, i|
            box = @boxes[c.id]
            unless i.zero?
              pair = [children[i - 1].id, c.id].sort
              base = related_pairs.include?(pair) ? related_gap : default_gap
              pos += [label_gaps[pair], base].compact.max
            end

            size = axis.size(box)
            pos += size / 2.0
            cross.set_position(box, centerline)
            axis.set_position(box, pos)
            pos += size / 2.0
          end
        end
      end
    end
  end
end
