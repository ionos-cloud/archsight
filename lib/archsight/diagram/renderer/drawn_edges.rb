# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # The already-relation-filtered edge list (`Renderer#drawn_edges`),
      # wrapped once and shared by `MarkerDefs` and `Stylesheet`, which
      # both read its relations and tinted lines.
      class DrawnEdges
        def initialize(edges)
          @edges = edges
        end

        # The drawn edges themselves, in declaration order -- `Stylesheet`
        # generates each one's hover highlight rule.
        def to_a = @edges

        def relations
          @relations ||= @edges.map(&:relation).uniq
        end

        # Every distinct (relation, tint name) pair among edges that opted
        # into an explicit `tint` -- shared by `MarkerDefs` (one colored
        # marker per pair) and `Stylesheet` (one stroke-override CSS rule
        # per pair), the same "compute it once, both callers read it back"
        # role `#relations` already plays.
        def tinted_lines
          @tinted_lines ||= @edges.filter_map { |e| [e.relation, e.tint] if e.tint }.uniq
        end
      end
    end
  end
end
