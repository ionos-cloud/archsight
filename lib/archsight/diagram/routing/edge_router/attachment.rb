# frozen_string_literal: true

require_relative "path_metrics"

module Archsight
  module Diagram
    module EdgeRouter
      # Box-attachment-point utilities used only for edge port-splitting
      # (`Renderer::EdgeRouting`/its successor) -- not part of candidate
      # generation or scoring.
      module Attachment
        module_function

        # Which side of `box` a path's endpoint sits on, or nil if it isn't
        # (within `PathMetrics::EDGE_EPSILON`) on any of them -- e.g. an
        # ellipse-inscribed anchor point (see `StraightPath.anchor_point`)
        # usually isn't exactly on the box's rectangular boundary except at
        # its four cardinal points, so port assignment simply skips those.
        def side_of(box, point)
          x, y = point
          return :left if PathMetrics.close?(x, box.left)
          return :right if PathMetrics.close?(x, box.right)
          return :top if PathMetrics.close?(y, box.top)
          return :bottom if PathMetrics.close?(y, box.bottom)

          nil
        end

        # Shifts a path's attachment point on `axis` (`:x` or `:y`) by
        # `delta`, at the start (`at: :start`) or end (`at: :end`) of
        # `points` -- used to move an edge off a box's default (centered)
        # attachment point when it shares that box's side with other edges.
        # Also shifts every point immediately after (or, from the end,
        # before) it that still shares the *original* coordinate on that
        # axis, since orthogonal routes keep a short run of points aligned
        # right after leaving (or before entering) a box -- e.g. a
        # single-turn route's exit point and its corner both sit at the same
        # y when exiting a left/right side, and need to move together to
        # stay a valid axis-aligned segment. A straight edge's 2-point path
        # has no such run, so only its lone endpoint moves.
        def shift_attachment(points, axis, delta, at:)
          idx = axis == :x ? 0 : 1
          ordered = at == :start ? points : points.reverse
          reference = ordered.first[idx]

          # Capped to `length - 1` so the far endpoint (the other box's own
          # attachment point) is never included, even when it happens to
          # share the same coordinate -- e.g. a 2-point straight edge that's
          # exactly horizontal/vertical, or `StraightPath.shared_edge_path`'s
          # output, which deliberately gives both endpoints the same
          # coordinate by construction. Without this cap the "run" swallows
          # the whole path and both ends move together.
          run_length = ordered.take(ordered.length - 1).take_while { |point| PathMetrics.close?(point[idx], reference) }.length
          shifted = ordered.each_with_index.map do |point, i|
            next point if i >= run_length

            point.dup.tap { |p| p[idx] += delta }
          end

          at == :start ? shifted : shifted.reverse
        end
      end
    end
  end
end
