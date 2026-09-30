# frozen_string_literal: true

module Archsight
  module Diagram
    class Layout
      # Per-container arrangement dispatch: a layer/stack is packed
      # deterministically (its declared order is part of its meaning),
      # everything else (a group, a boundary, `TopLevel`) goes to
      # `ForceSimulation` --
      # unless the container's `ranks` mode (the top level's own comes from
      # `top_level_ranks`, see `Graph#ranks_mode`) has its children laid out
      # in ranks by `RankedArranger` instead:
      #
      # - `down`/`right`: always, in that direction;
      # - `on`: always, in the container's natural one -- a layer's ranks
      #   run left to right, everything else's top to bottom;
      # - `auto` (the default): a group/boundary/the top level whenever its
      #   children form a deep enough DAG (`RankedArranger#auto_direction`);
      #   never a layer/stack, whose own declared order is deliberate;
      # - `off`: never.
      class RankArranger
        # Every container `arrange_children` ranked (`TopLevel` included),
        # by id -- `Layout`/`Globalizer` leave their arrangement alone.
        attr_reader :ranked

        def initialize(boxes, rank_topology:, force_simulation:, ranked_arranger:, theme:, top_level_ranks: nil)
          @boxes = boxes
          @theme = theme
          @rank_topology = rank_topology
          @force_simulation = force_simulation
          @ranked_arranger = ranked_arranger
          @top_level_ranks = top_level_ranks || "auto"
          @ranked = {}.compare_by_identity
        end

        def arrange_children(node, children)
          if (direction = rank_direction(node, children))
            @ranked[node] = true
            return @ranked_arranger.arrange(node, children, direction)
          end

          if node.layer?
            arrange_layer(node, children)
          elsif node.stack?
            arrange_stack(node, children)
          else
            @force_simulation.arrange(node, children)
          end
        end

        private

        def rank_direction(node, children)
          mode = node.top_level? ? @top_level_ranks : node.ranks_mode
          case mode
          when "down" then :down
          when "right" then :right
          when "on" then node.layer? ? :right : :down
          when "auto"
            @ranked_arranger.auto_direction(node, children) unless node.ranked?
          end
        end

        # Peers at the same rank: packed left-to-right in declaration order
        # (no physics needed for "equal-weight siblings"), all sharing one
        # centerline so mixed heights still align visually. Not stretched
        # to a common height by default the way a stack's ranks are
        # stretched to a common width: forcing every sibling in a row to the
        # tallest one's height mostly just pads out the shorter ones with
        # dead space. A child opts in with `extend "height"` instead -- only
        # its own box grows (its content stays top-aligned, where
        # `fit_group_and_normalize_children` already put it), and the shared
        # centerline then lines its top/bottom up with the tallest sibling's.
        def arrange_layer(group, children)
          max_height = children.map { |c| @boxes[c.id].height }.max
          children.each do |c|
            @boxes[c.id].height = max_height if !c.leaf? && c.extend_height?
          end

          gap = group.gap(@theme.sibling_gap)
          Stacker.new(@boxes).pack(
            children, axis: Axis::WIDTH, default_gap: gap, related_gap: gap,
                      label_gaps: @rank_topology.label_gap_requirements(group, children)
          )
        end

        # "Runs on top of": packed top-to-bottom in declaration order (first
        # declared ends up on top, consistent with the tool's top-down reading
        # convention), every child stretched to the stack's widest child for a
        # clean tower look. Adjacent ranks *directly* connected by an edge
        # (e.g. a call/dependency drawn as an arrow) need enough room for
        # that arrow to actually be visible — the stack gap alone is smaller than
        # an arrowhead — so they get the sibling gap instead, and a direct
        # labeled edge gets room for its label. Everything else, including a
        # pair of composite ranks that merely have *some* descendant-to-
        # descendant edge between them (as opposed to the ranks themselves
        # being the edge's endpoints), keeps the tight, touching "tower"
        # look: that inner edge is drawn wherever its actual endpoints ended
        # up, not necessarily through the narrow strip between the ranks, so
        # widening the strip for it doesn't reliably help and just leaves an
        # oversized gap.
        def arrange_stack(group, children)
          return if children.empty?

          max_width = children.map { |c| @boxes[c.id].width }.max
          expander = Expander.new(@boxes, theme: @theme)
          extend = group.extend?(false)
          children.each { |c| expander.expand(c, Axis::WIDTH, max_width, inherited: extend) }

          rank_edges = @rank_topology.rank_edges_between(children)
          Stacker.new(@boxes).pack(
            children, axis: Axis::HEIGHT, default_gap: group.gap(@theme.stack_gap),
                      related_gap: group.gap(@theme.sibling_gap),
                      label_gaps: @rank_topology.rank_label_gaps(rank_edges),
                      related_pairs: rank_edges.map { |(ra, rb, _e)| [ra.id, rb.id].sort }
          )
        end
      end
    end
  end
end
