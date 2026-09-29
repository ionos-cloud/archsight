# frozen_string_literal: true

require_relative "../style/representers"
require_relative "../support/geometry"
require_relative "edge_router/path_metrics"
require_relative "edge_router/straight_path"
require_relative "edge_router/bridge_path"
require_relative "edge_router/orthogonal_path"
require_relative "edge_router/attachment"
require_relative "../native"

module Archsight
  module Diagram
    # Computes an SVG path (a list of [x, y] points) between two boxes for a
    # given edge style ("straight" or "orthogonal"), routed between the
    # nearest edges of the two boxes rather than their centers.
    #
    # Shapes that render as an ellipse (`circle`, `actor`, per their
    # Representer's `elliptical?`) need an elliptical anchor formula instead
    # of the rectangular-boundary one; everything else (including
    # `cylinder`/`pipe`, whose exact outline isn't worth the extra math) is
    # treated as a rectangle for anchoring purposes.
    module EdgeRouter
      module_function

      # `style` is `"straight"` or `"orthogonal"` to force that family, or
      # nil (unset in the DSL) to pick automatically: every candidate path
      # in the requested (or, if unset, either) family is generated, and
      # whichever draws over the fewest `obstacles` (other boxes it isn't
      # actually connecting) wins -- the way a human deciding by eye
      # between a direct line and a right-angle one would, rather than a
      # fixed rule about how long or diagonal the edge itself is. Ties
      # (including "no candidate is fully clear") favor the simplest
      # shape: straight, then a single turn, then a two-turn mid-jog or
      # bridge.
      def route(from_box, to_box, style, from_shape: "rectangle", to_shape: "rectangle", obstacles: [], sibling_paths: [])
        candidates = candidate_paths(from_box, to_box, style, from_shape: from_shape, to_shape: to_shape, obstacles: obstacles)
        best_path(candidates, obstacles, sibling_paths: sibling_paths)
      end

      def candidate_paths(a, b, style, from_shape: "rectangle", to_shape: "rectangle", obstacles: [])
        # A straight axis-aligned line joins the straight family (and the
        # automatic choice), listed first so it wins ties against the
        # diagonal. An explicit `style "orthogonal"` keeps its bends.
        aligned = StraightPath.aligned_paths(a, b, from_shape: from_shape, to_shape: to_shape)
        straight = [StraightPath.straight_path(a, b, from_shape: from_shape, to_shape: to_shape)]
        orthogonal = OrthogonalPath.orthogonal_candidates(a, b, obstacles)

        case style
        when "straight" then aligned + straight
        when "orthogonal" then orthogonal
        else aligned + straight + orthogonal
        end
      end

      # Avoiding a crossing is worth a *reasonable* detour, not an
      # unbounded one -- treated as a strict priority (0 crossings always
      # beating 1, however long the detour), a bridge routed hundreds of
      # pixels out of its way to dodge a box a straight line barely grazes
      # reads far worse than just accepting that graze. Weighting each
      # crossing as equivalent to this many extra pixels of travel gives a
      # real trade-off instead: a short detour still wins, but a drastic
      # one loses to tolerating a crossing or two. Roughly one node's
      # width plus its gap to a neighbor.
      CROSSING_PENALTY = 200.0

      # Among routes that draw over the same number of boxes, every bend
      # beyond the fewest bends any of them needs costs this many extra
      # pixels of length -- so a one-corner route wins over a zig-zag (with
      # its short stub into the target) unless it is over this much longer.
      # Charged relative to the best candidate in the same crossing class
      # rather than absolutely, so however large it is it never tips the
      # balance against `CROSSING_PENALTY`: a bridge that clears a box still
      # beats a bend-free line through it.
      TURN_PENALTY = 300.0

      # Two edges running right along each other for a stretch reads as
      # clutter too, but far more mildly than either one cutting through a
      # box -- weighting each pixel of *collinear* overlap with a sibling
      # edge's line this much (well under `CROSSING_PENALTY`, a bit above
      # plain length's implicit 1x) lets a candidate shed real overlap by
      # trading a modest bit of extra length, without it ever outweighing
      # box-crossing avoidance or triggering a drastic detour on its own.
      LINE_OVERLAP_PENALTY = 2.0
      # A blended score (like `CROSSING_PENALTY` folded straight into
      # `path_length`) can't work for overlap too: however small a weight
      # or cap it's given, a long enough shared run would still eventually
      # out-penalize a candidate that's only *slightly* better on
      # crossings/length -- accepting a box crossing just to dodge a
      # sibling's line, which is exactly backwards ("not as important as
      # component overlap"). So overlap only ever chooses among candidates
      # that don't cost any *extra* crossings versus the best available --
      # never a reason to accept a worse crossing count -- plus any
      # candidate close enough to the best crossing+length score that
      # `route` would have called it a reasonable trade-off on its own
      # (see `CROSSING_PENALTY`'s doc comment): overlap can nudge a choice
      # within that band, never past it.
      OVERLAP_TIE_TOLERANCE = 40.0

      # Two edges' lines properly crossing (an X, not just running
      # alongside each other) is a distinct visual defect from overlap,
      # worth avoiding independently -- a flat cost per crossing, not
      # per-pixel like overlap, since the clutter is the crossing itself
      # regardless of the angle it happens at. Governed by the same
      # `contenders` guardrail as overlap: never a reason to accept a
      # worse box-crossing count, only to choose among candidates that
      # are already fine on that front.
      LINE_CROSSING_PENALTY = 50.0

      def best_path(candidates, obstacles, sibling_paths: [])
        select_best(score_candidates(candidates, obstacles), sibling_paths: sibling_paths)
      end

      # The `{path:, crossing:, length:}` scoring `select_best` needs, split
      # out on its own since it depends only on `candidates`/`obstacles` --
      # never on `sibling_paths` -- so a caller re-selecting the same edge's
      # best route as siblings settle into place (`EdgeRouting#refine_line_overlap!`)
      # can compute it once and feed it to `select_best` on every round,
      # instead of rebuilding identical candidate geometry and rescoring it
      # against the same, unchanged `obstacles` each time. The crossing
      # counts and lengths come from `Native.score_paths` in one packing when
      # the native kernels are built.
      def score_candidates(candidates, obstacles)
        crossings, lengths = Native.score_paths(candidates, obstacles)
        crossings ||= candidates.map { |path| PathMetrics.crossing_count(path, obstacles) }
        lengths ||= candidates.map { |path| Geometry.path_length(path) }
        turns = candidates.map { |path| Geometry.turn_count(path) }
        fewest_turns = crossings.zip(turns).group_by(&:first).transform_values { |pairs| pairs.map(&:last).min }
        candidates.each_with_index.map do |path, i|
          # Folded into `length` (rather than a separate term) so the native
          # selection kernels, which only know crossings and length, apply it too.
          extra_turns = turns[i] - fewest_turns[crossings[i]]
          { path: path, crossing: crossings[i], length: lengths[i] + (TURN_PENALTY * extra_turns) + off_center_cost(path) }
        end
      end

      # What an off-center entry saves in length over the centered one (see
      # `OrthogonalPath::OffCenterPath`), plus a hair so a tie always goes
      # to the centered route despite float rounding.
      def off_center_cost(path)
        path.is_a?(OrthogonalPath::OffCenterPath) ? path.entry_offset + 0.01 : 0.0
      end

      # Picks the best already-`score_candidates`d path, scoring `contenders`
      # against `sibling_paths` in their original (tie-break) order and
      # tracking the best score seen so far. Every scoring term
      # (`overlap_length`, `crossing_edges_count`, `crossing` and `length`
      # themselves) is >= 0, so a contender's own crossing + length score
      # alone is already a lower bound on its total score -- once it's no better than the current best, no amount
      # of sibling-clearance can save it, so its (expensive, O(segments x
      # siblings) `overlap_length`/`crossing_edges_count`) score is never
      # computed. This changes nothing about the result: skipped contenders
      # could only ever fail to beat the running best anyway.
      #
      # With sibling paths to score against (`DataflowRouting`'s hop
      # segments), `Native.select_best` makes the same choice in C when the
      # native kernels are built.
      def select_best(scored, sibling_paths: [])
        index = Native.select_best(scored, sibling_paths)
        return scored[index][:path] if index

        min_crossing = scored.map { |s| s[:crossing] }.min
        best_primary = scored.map { |s| (s[:crossing] * CROSSING_PENALTY) + s[:length] }.min

        contenders = scored.select do |s|
          s[:crossing] == min_crossing || ((s[:crossing] * CROSSING_PENALTY) + s[:length]) <= best_primary + OVERLAP_TIE_TOLERANCE
        end

        best_path = nil
        best_score = Float::INFINITY

        contenders.each do |s|
          # The contender's own crossing + length score, not length alone: a
          # candidate inside the band that draws over more boxes must not
          # win on being shorter.
          primary = (s[:crossing] * CROSSING_PENALTY) + s[:length]
          next if primary >= best_score

          score = (PathMetrics.overlap_length(s[:path], sibling_paths) * LINE_OVERLAP_PENALTY) +
                  (PathMetrics.crossing_edges_count(s[:path], sibling_paths) * LINE_CROSSING_PENALTY) +
                  primary
          next unless score < best_score

          best_score = score
          best_path = s[:path]
        end

        best_path
      end

      # How many (segment, obstacle) pairs one path draws through -- the
      # "amount of visual clutter" it causes (see `PathMetrics.crossing_count`,
      # the reference) -- through `Native.crossing_counts` when the native
      # kernels are built. `EdgeRouting#shift_for` checks a shifted port
      # with it.
      def crossing_count(points, obstacles)
        Native.crossing_counts([points], obstacles)&.first || PathMetrics.crossing_count(points, obstacles)
      end
    end
  end
end
