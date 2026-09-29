# frozen_string_literal: true

module Archsight
  module Diagram
    class Layout
      # Iteratively pushes apart any pair of boxes still overlapping after
      # positioning, along whichever axis needs the smaller nudge,
      # respecting a per-pair minimum gap (so a labeled edge's text has
      # room to render between its two boxes).
      class OverlapResolver
        def initialize(boxes, theme:)
          @boxes = boxes
          @theme = theme
        end

        # `label_gaps` (unordered [id, id] pair => minimum gap) lets a pair of
        # siblings connected by a labeled edge require more separation than
        # `default_gap`, so the label has room to render between their boxes
        # instead of overlapping them -- only ever more: a label gap smaller
        # than `default_gap` (e.g. a group's explicit `gap`) doesn't shrink it.
        def resolve_overlaps(children, label_gaps: {}, default_gap: @theme.sibling_gap, iterations: 150)
          iterations.times do
            moved = false
            children.combination(2).each do |a, b|
              ba = @boxes[a.id]
              bb = @boxes[b.id]
              gap = [label_gaps[[a.id, b.id].sort], default_gap].compact.max
              overlap_x = ba.overlap_on(Axis::WIDTH, bb, gap: gap)
              overlap_y = ba.overlap_on(Axis::HEIGHT, bb, gap: gap)
              next unless overlap_x.positive? && overlap_y.positive?

              moved = true
              if overlap_x < overlap_y
                shift = overlap_x / 2.0
                shift = -shift if ba.x < bb.x
                ba.x += shift
                bb.x -= shift
              else
                shift = overlap_y / 2.0
                shift = -shift if ba.y < bb.y
                ba.y += shift
                bb.y -= shift
              end
            end
            break unless moved
          end
        end
      end
    end
  end
end
