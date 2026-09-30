# frozen_string_literal: true

require_relative "../support/text_metrics"
require_relative "../support/geometry"
require_relative "../native"
require_relative "../routing/edge_router/path_metrics"

module Archsight
  module Diagram
    class Renderer
      # Overlap-avoiding label placement along a path -- tries a few
      # candidate positions (biased toward the source/target ends, since a
      # label planted dead center is often exactly where it's most likely
      # to cover something) and picks whichever one overlaps the fewest
      # node boxes or already-placed labels, tracking its own running list
      # of placements so later calls avoid earlier ones too -- and, once
      # every line in the diagram has been handed to `register_paths`, the
      # fewest *other* lines too, so a label never sits where a reader
      # could take it for a neighbouring line's.
      class LabelPlacer
        # Candidate positions (as a fraction of the line's total length)
        # tried for a label, in priority order: the two closest to the
        # source/target ends first, true midpoint as a fallback, then more
        # extreme source/target-biased positions for when even those
        # overlap something.
        # `0.15`/`0.85` come last: close enough to the ends to risk crowding
        # the arrowhead, so only worth it when everything further in sits on
        # or beside some other line.
        LABEL_FRACTION_CANDIDATES = [0.35, 0.65, 0.5, 0.25, 0.75, 0.15, 0.85].freeze

        # Below this total path length, biasing toward source/target risks
        # landing the label on (or past) the node it's leaving/entering, so
        # only the plain midpoint is tried.
        MIN_LENGTH_FOR_LABEL_BIAS = 80.0

        # Same flat char-width heuristic style as `Layout::EDGE_LABEL_CHAR_WIDTH`,
        # used here for a cheap label bounding-box estimate rather than real
        # glyph metrics -- good enough to steer overlap avoidance, not to pin
        # exact pixel edges.
        LABEL_CHAR_WIDTH = 6.5

        # A foreign line this close to a label (without actually crossing
        # it) still reads as possibly the line the label belongs to.
        LABEL_PATH_CLEARANCE = 6.0
        # What a foreign line costs a candidate position, in the same units
        # as an overlapped node box or label (1 each): a line crossing the
        # label counts fully, one merely running close by half.
        PATH_CROSSING_PENALTY = 1.0
        PATH_NEARBY_PENALTY = 0.5
        # A label on, or right up against, a group's/boundary's dashed
        # border reads as squeezed onto it -- but stays unambiguous, so it's
        # cheaper than sitting on another edge's line. "Right up against" is
        # a wider margin than `LABEL_PATH_CLEARANCE`: a label's estimated
        # box stops at its baseline, and descenders hang below that.
        CONTAINER_BORDER_PENALTY = 0.5
        CONTAINER_BORDER_CLEARANCE = 10.0
        # A label sitting on its own line's bend has that line running
        # through it twice -- in along one leg, out along the other --
        # instead of just alongside (or, on a vertical run, straight
        # through once, which every such label does by design).
        OWN_BEND_PENALTY = 0.5

        # A label's box as `PathMetrics.segment_crosses_box?` wants it (and,
        # since a Struct also answers `[:left]`, as `Native.pack_rects` does).
        Rect = Struct.new(:left, :right, :top, :bottom)

        # `boxes` is every solid node's computed box (a Hash id => Box), used
        # to score a candidate label position against every node on the
        # diagram, not just the ones the label's own path touches.
        # `containers` (same shape) are the drawn groups/boundaries: a label
        # sitting well inside one is fine -- most labels do -- so one only
        # counts when the label sits on or close to its border.
        def initialize(boxes, containers: {})
          @boxes = boxes
          @containers = containers.values.map { |c| [c.left, c.right, c.top, c.bottom] }
          @paths = []
          @path_bounds = []
          @placed_label_boxes = []
          # `@placed_label_boxes` again, prepacked for `Native.rect_overlap_counts`
          # (one 32-byte append per placement) when the native kernels are built.
          @placed_native = String.new(encoding: Encoding::BINARY) if Native.available?
        end

        # A multi-line label (`\n`-separated, see `TextRenderer#text_content_markup`)
        # is rendered as several stacked `<tspan>`s centered around `y`, not
        # a single line sitting above it -- estimating its box as if it
        # were still one line underestimates a multi-line label's true
        # vertical extent, letting two such labels overlap undetected.
        # `line_height` matches `text_content_markup`'s own spacing exactly,
        # so `n == 1` reduces to the original one-line box
        # (`top: y - line_height, bottom: y`) unchanged.
        def self.label_bbox(x, y, text, font_size)
          line_height = font_size * TextRenderer::LABEL_LINE_HEIGHT_EM
          w = TextMetrics.width(text, char_width: LABEL_CHAR_WIDTH * (font_size / 11.0))
          half_spread = TextMetrics.extra_height(text, line_height: line_height) / 2.0
          { left: x - (w / 2), right: x + (w / 2), top: y - half_spread - line_height, bottom: y + half_spread }
        end

        def self.rects_intersect?(a, b)
          b_left = b.is_a?(Hash) ? b[:left] : b.left
          b_right = b.is_a?(Hash) ? b[:right] : b.right
          b_top = b.is_a?(Hash) ? b[:top] : b.top
          b_bottom = b.is_a?(Hash) ? b[:bottom] : b.bottom
          a[:left] < b_right && a[:right] > b_left && a[:top] < b_bottom && a[:bottom] > b_top
        end

        # Every line in the diagram -- plain edges, implements-tree
        # segments, dataflows -- as point lists, registered before any label
        # is placed so each one avoids lines drawn after it too. A label
        # never avoids its own line: `place_label_along` skips the very
        # `points` object it was handed.
        #
        # Packed once, here, for `Native.path_rect_hits` when the native
        # kernels are built -- a dense diagram has hundreds of lines, tested
        # against every candidate of every label. The Ruby fallback keeps
        # each line's bounding box instead, to skip the far-away ones.
        def register_paths(paths)
          paths.each do |path|
            @paths << path
            lo_x, hi_x, lo_y, hi_y = EdgeRouter::PathMetrics.bounding_box(path)
            @path_bounds << Rect.new(lo_x, hi_x, lo_y, hi_y)
          end
          @packed_paths = Native.pack_paths(@paths) if Native.available?
        end

        # Picks the first (in priority order, see `LABEL_FRACTION_CANDIDATES`)
        # position along `points` with no overlaps, falling back to whichever
        # candidate overlaps the least -- a label is always placed somewhere,
        # never skipped, matching the previous fixed-midpoint behavior.
        def place_label_along(points, label, font_size: 11)
          return unless label

          total = Geometry.path_length(points)
          fractions = total < MIN_LENGTH_FOR_LABEL_BIAS ? [0.5] : LABEL_FRACTION_CANDIDATES

          candidates = fractions.map do |f|
            pt = Geometry.point_along(points, f)
            [pt, LabelPlacer.label_bbox(pt[0], pt[1] - 6, label, font_size)]
          end
          native_scores = native_overlap_scores(candidates.map(&:last))
          path_scores = path_scores(candidates.map(&:last), points)

          best = nil
          best_score = Float::INFINITY
          candidates.each_with_index do |(pt, box), i|
            score = (native_scores ? native_scores[i] : label_overlap_score(box)) + border_score(box) + path_scores[i] +
                    bend_score(box, points)
            if score < best_score
              best = pt
              best_score = score
            end
            break if score.zero?
          end

          placed = LabelPlacer.label_bbox(best[0], best[1] - 6, label, font_size)
          @placed_label_boxes << placed
          @placed_native << Native.pack_rects([placed]) if @placed_native
          best
        end

        private

        # Every candidate's `label_overlap_score` in one native call, or nil
        # when the kernels aren't built. The node boxes are packed on first
        # use -- they're final by the time any label is placed.
        def native_overlap_scores(label_boxes)
          return nil unless @placed_native

          @node_table ||= Native.pack_boxes(@boxes.values)
          Native.rect_overlap_counts(label_boxes, @node_table, @placed_native)
        end

        # What the container borders on or near a candidate label `box`
        # cost it (see `CONTAINER_BORDER_PENALTY`).
        def border_score(box)
          m = CONTAINER_BORDER_CLEARANCE
          left = box[:left] - m
          right = box[:right] + m
          top = box[:top] - m
          bottom = box[:bottom] + m
          touched = @containers.count do |c_left, c_right, c_top, c_bottom|
            # Overlapping it (strictly, as `rects_intersect?`), but not
            # wholly inside it.
            left < c_right && right > c_left && top < c_bottom && bottom > c_top &&
              !(left >= c_left && right <= c_right && top >= c_top && bottom <= c_bottom)
          end
          touched * CONTAINER_BORDER_PENALTY
        end

        # See `OWN_BEND_PENALTY`.
        def bend_score(box, points)
          return 0 if points.length < 3

          rect = Rect.new(box[:left], box[:right], box[:top], box[:bottom])
          through = points.each_cons(2).count { |(x1, y1), (x2, y2)| EdgeRouter::PathMetrics.segment_crosses_box?(x1, y1, x2, y2, rect) }
          through > 1 ? OWN_BEND_PENALTY : 0
        end

        # What every registered line but `own` costs each candidate label
        # box in `boxes`: see `PATH_CROSSING_PENALTY`/`PATH_NEARBY_PENALTY`.
        # Each box is tested as-is and grown by `LABEL_PATH_CLEARANCE`; a line
        # crossing the box itself necessarily crosses the grown one too, so
        # the two counts give crossing and merely-nearby lines apart.
        def path_scores(boxes, own)
          return Array.new(boxes.length, 0) if @paths.empty?

          c = LABEL_PATH_CLEARANCE
          rects = boxes.flat_map do |box|
            [Rect.new(box[:left], box[:right], box[:top], box[:bottom]),
             Rect.new(box[:left] - c, box[:right] + c, box[:top] - c, box[:bottom] + c)]
          end
          own_index = @paths.index { |path| path.equal?(own) } || -1
          hits = @packed_paths ? Native.path_rect_hits(@packed_paths, rects, own_index) : rects.map { |r| path_hit_count(r, own_index) }

          hits.each_slice(2).map do |crossing, near|
            (crossing * PATH_CROSSING_PENALTY) + ((near - crossing) * PATH_NEARBY_PENALTY)
          end
        end

        # How many registered lines, all but index `own`, cross `rect`.
        def path_hit_count(rect, own)
          @paths.each_index.count do |i|
            next false if i == own

            b = @path_bounds[i]
            b.left <= rect.right && b.right >= rect.left && b.top <= rect.bottom && b.bottom >= rect.top && path_hits?(@paths[i], rect)
          end
        end

        def path_hits?(path, rect)
          path.each_cons(2).any? do |(x1, y1), (x2, y2)|
            [x1, x2].max >= rect.left && [x1, x2].min <= rect.right && [y1, y2].max >= rect.top && [y1, y2].min <= rect.bottom &&
              EdgeRouter::PathMetrics.segment_crosses_box?(x1, y1, x2, y2, rect)
          end
        end

        # How many node boxes or already-placed labels a candidate label
        # position would overlap -- lower is better, zero means it's fully
        # clear.
        def label_overlap_score(box)
          count = @boxes.each_value.count { |b| LabelPlacer.rects_intersect?(box, b) }
          count + @placed_label_boxes.count { |b| LabelPlacer.rects_intersect?(box, b) }
        end
      end
    end
  end
end
