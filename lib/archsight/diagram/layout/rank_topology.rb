# frozen_string_literal: true

module Archsight
  module Diagram
    class Layout
      # Maps graph edges onto whichever ranks/children are currently being
      # arranged -- the one cluster of helpers shared by rank arrangement
      # (`RankArranger`), the force simulation (`ForceSimulation`), root
      # alignment (`RootAlignment`), and globalization (`Globalizer`)
      # alike.
      class RankTopology
        def initialize(graph, boxes, theme:)
          @graph = graph
          @boxes = boxes
          @theme = theme
        end

        # Edges plus synthetic hop-to-hop edges from every dataflow (tagged
        # with the "data" relation purely so `ForceSimulation#apply_flow`'s
        # bias and any relation-keyed fallback behave sanely) -- gives
        # consecutive hops the exact same attraction/flow/align/gap-sizing
        # forces a real edge gets, with no separate simulation path.
        # Layout-only: dataflows are drawn by the renderer's own pass,
        # independent of `Graph::Edge`.
        def attraction_edges
          @attraction_edges ||= @graph.edges + @graph.dataflows.flat_map do |df|
            df.hops.each_cons(2).map do |a, b|
              Graph::Edge.new(from: a, to: b, attrs: { "relation" => "data" }, direction: :directed)
            end
          end
        end

        # Edges whose endpoints each resolve to one of `children` (a rank) —
        # either literally (the edge's own endpoint is the rank) or nested
        # directly inside an *anonymous* rank, which renders no box of its
        # own and so has no padding to give an edge crossing near it room to
        # breathe, same as if the edge touched the rank itself. A *named*
        # container's own padding already provides that room, so an edge
        # merely nested inside one (at any depth) doesn't widen the gap
        # between ranks — see the "keeps the tight default gap..." test.
        def rank_edges_between(children)
          ids = children.map(&:id)
          attraction_edges.filter_map do |e|
            ra = anonymous_transparent_rank(e.from, ids)
            rb = anonymous_transparent_rank(e.to, ids)
            next unless ra && rb && ra.id != rb.id

            [ra, rb, e]
          end
        end

        # A rank-to-rank edge's label sits beside the (mostly vertical) line,
        # not along it, so the gap it needs is a fixed allowance for one line
        # of text -- not proportional to the label string's length the way a
        # *horizontal* sibling gap is (see `label_gap_requirements`), or a
        # long label would blow the vertical gap open far past what the text
        # actually needs.
        def rank_label_gaps(rank_edges)
          gaps = {}
          rank_edges.each do |ra, rb, e|
            next unless e.label

            key = [ra.id, rb.id].sort
            gaps[key] = [gaps[key] || 0.0, @theme.rank_edge_label_gap].max
          end
          gaps
        end

        # Finds the ancestor of `node` that is a direct child of `group`
        # (`TopLevel` meaning "top level"), i.e. the box that represents
        # `node` inside `group`'s own simulation. Returns nil if `node` is
        # not inside `group`.
        def representative_in(group, node)
          chain = ancestor_chain(node)
          if group.top_level?
            chain.first
          else
            idx = chain.index(group)
            return nil unless idx
            return nil if idx == chain.length - 1

            chain[idx + 1]
          end
        end

        def relevant_edges(group, children)
          attraction_edges.filter_map do |e|
            ra = representative_in(group, e.from)
            rb = representative_in(group, e.to)
            next unless ra && rb && !ra.equal?(rb)
            next unless children.include?(ra) && children.include?(rb)

            [ra, rb, e.relation]
          end
        end

        # For each pair of `children` directly connected by a labeled edge,
        # the minimum gap needed for that label's text to fit between them.
        def label_gap_requirements(group, children)
          gaps = {}

          attraction_edges.each do |e|
            next unless e.label

            ra = representative_in(group, e.from)
            rb = representative_in(group, e.to)
            next unless ra && rb && !ra.equal?(rb)
            next unless children.include?(ra) && children.include?(rb)

            width = (e.label.length * @theme.edge_label_char_width) + @theme.edge_label_gap_padding
            key = [ra.id, rb.id].sort
            gaps[key] = [gaps[key] || 0.0, width].max
          end

          gaps
        end

        private

        def anonymous_transparent_rank(node, rank_ids)
          return node if rank_ids.include?(node.id)

          cur = node.parent
          while cur&.anonymous?
            return cur if rank_ids.include?(cur.id)

            cur = cur.parent
          end
          nil
        end

        # Root-first, `node` last (the reverse of `Node#ancestors`' own
        # self-first order).
        def ancestor_chain(node) = node.ancestors.reverse
      end
    end
  end
end
