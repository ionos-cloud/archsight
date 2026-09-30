# frozen_string_literal: true

module Archsight
  module Diagram
    class Layout
      # A container's children laid out in ranks by the edges between them
      # (see `ranks` in the README) -- Sugiyama-style, the way a DAG reads
      # best: every edge points from one rank to a later one, so a whole
      # dependency chain reads top to bottom (`:down`) or left to right
      # (`:right`) instead of wherever a force simulation left it.
      #
      # 1. The children's own digraph: every edge between two of their
      #    descendants becomes one between the two children containing
      #    them, "above" to "below" -- the dependent above its dependency,
      #    as in a `stack`, except `implements` (`inverted_flow?`), whose
      #    interface sits above its implementers.
      # 2. Cycles broken by reversing a declaration-order DFS's back edges.
      # 3. Ranks by longest path from the sources.
      # 4. A dummy node per rank a longer edge skips, so ordering sees the
      #    edge passing through and coordinates keep a lane open for it.
      # 5. Each rank's order: barycenter sweeps, keeping whichever order
      #    crossed the fewest edges.
      # 6. Coordinates: ranks `rank_gap` apart along the main axis; along
      #    the cross axis every node is pulled toward its neighbours in the
      #    adjacent ranks, never closer than `sibling_gap` to the next node
      #    in its own rank.
      class RankedArranger
        # How much room a long edge's dummy node reserves in a rank it
        # passes through -- a lane between the nodes on either side.
        RANK_LANE = 16.0
        ORDER_SWEEPS = 12
        ALIGN_PASSES = 8
        # `auto` only ranks a container when this many ranks come out -- a
        # one- or two-step chain reads fine however it's arranged (an
        # explicit `ranks "on"`/`"down"`/`"right"` still ranks one).
        AUTO_MIN_RANKS = 3

        Vertex = Struct.new(:node, :rank, :order_key, :main, :cross, :up, :down, keyword_init: true) do
          def dummy? = node.nil?
        end

        def initialize(graph, boxes, rank_topology:, theme:)
          @graph = graph
          @boxes = boxes
          @rank_topology = rank_topology
          @theme = theme
        end

        # `:down` when `children`'s own digraph is acyclic and at least
        # `AUTO_MIN_RANKS` deep -- `ranks "auto"`'s rule -- else nil.
        def auto_direction(group, children)
          edges = child_edges(group, children)
          return nil if edges.empty? || cyclic?(children, edges)

          ranks(children, edges).values.max + 1 >= AUTO_MIN_RANKS ? :down : nil
        end

        def arrange(group, children, direction)
          return if children.empty?

          edges = acyclic(children, child_edges(group, children))
          rank_of = ranks(children, edges)
          vertices, layers = build_layers(children, edges, rank_of, direction)
          order(layers)
          place(group, vertices, layers, edges, rank_of, direction)
        end

        private

        # `[above, below, labeled?]` per distinct pair of children an edge
        # joins, in edge declaration order.
        def child_edges(group, children)
          members = children.to_h { |c| [c.id, c] }
          pairs = {}
          @graph.edges.each do |e|
            a = @rank_topology.representative_in(group, e.from)
            b = @rank_topology.representative_in(group, e.to)
            next unless a && b && members[a.id] && members[b.id] && !a.equal?(b)

            a, b = b, a if e.relation_type.inverted_flow?
            key = [a.id, b.id]
            pairs[key] = [a, b, pairs.dig(key, 2) || !e.label.nil?]
          end
          pairs.values
        end

        def cyclic?(children, edges)
          ids = ->(list) { list.map { |a, b, _| [a.id, b.id] } }
          ids.call(acyclic(children, edges)) != ids.call(edges)
        end

        # `edges` with every back edge of a declaration-order DFS reversed
        # (and any pair that then duplicates another dropped).
        def acyclic(children, edges)
          out = Hash.new { |h, k| h[k] = [] }
          edges.each_with_index { |(a, b, _), i| out[a.id] << [b, i] }
          state = {}
          reversed = {}
          visit = lambda do |node|
            state[node.id] = :open
            out[node.id].each do |target, i|
              case state[target.id]
              when :open then reversed[i] = true
              when nil then visit.call(target)
              end
            end
            state[node.id] = :done
          end
          children.each { |c| visit.call(c) unless state[c.id] }

          seen = {}
          edges.each_with_index.filter_map do |(a, b, labeled), i|
            a, b = b, a if reversed[i]
            next if seen[[a.id, b.id]]

            seen[[a.id, b.id]] = true
            [a, b, labeled]
          end
        end

        # Longest path from the sources, by child id.
        def ranks(children, edges)
          preds = Hash.new { |h, k| h[k] = [] }
          edges.each { |a, b, _| preds[b.id] << a.id }
          rank_of = {}
          visiting = {}
          rank = lambda do |id|
            return rank_of[id] if rank_of.key?(id)
            return 0 if visiting[id] # only reachable for a cyclic input, see `auto_direction`

            visiting[id] = true
            rank_of[id] = preds[id].map { |p| rank.call(p) + 1 }.max || 0
          end
          children.each { |c| rank.call(c.id) }
          rank_of
        end

        # One vertex per child, plus a dummy per rank a longer edge skips;
        # `layers[r]` holds rank `r`'s vertices, in declaration order to
        # start with (isolated children last in rank 0).
        def build_layers(children, edges, rank_of, direction)
          connected = edges.flat_map { |a, b, _| [a.id, b.id] }.to_h { |id| [id, true] }
          vertices = children.each_with_index.to_h do |c, i|
            box = @boxes[c.id]
            main, cross = direction == :down ? [box.height, box.width] : [box.width, box.height]
            key = connected[c.id] ? i : children.length + i
            [c.id, Vertex.new(node: c, rank: rank_of[c.id], order_key: key, main: main, cross: cross, up: [], down: [])]
          end

          all = vertices.values
          edges.each do |a, b, _|
            from = vertices[a.id]
            to = vertices[b.id]
            chain = ((from.rank + 1)...to.rank).map do |r|
              Vertex.new(node: nil, rank: r, order_key: from.order_key + 0.5, main: 0.0, cross: RANK_LANE, up: [], down: [])
            end
            all.concat(chain)
            [from, *chain, to].each_cons(2) do |upper, lower|
              upper.down << lower
              lower.up << upper
            end
          end

          layers = Array.new(all.map(&:rank).max + 1) { [] }
          all.sort_by(&:order_key).each { |v| layers[v.rank] << v }
          [vertices, layers]
        end

        # Barycenter sweeps, alternating down and up; `layers` ends in
        # whichever order crossed the fewest edges.
        def order(layers)
          best = layers.map(&:dup)
          best_crossings = crossings(layers)

          ORDER_SWEEPS.times do |sweep|
            ranks = (1...layers.length).to_a
            ranks = ranks.reverse.map { |r| r - 1 } if sweep.odd?
            ranks.each do |r|
              neighbours = sweep.even? ? :up : :down
              position = positions(layers[sweep.even? ? r - 1 : r + 1])
              layers[r] = layers[r].each_with_index.sort_by do |v, i|
                ns = v.send(neighbours)
                [ns.empty? ? i : ns.sum { |n| position[n] } / ns.length.to_f, i]
              end.map(&:first)
            end

            count = crossings(layers)
            next unless count < best_crossings

            best = layers.map(&:dup)
            best_crossings = count
          end

          layers.replace(best)
        end

        # Each vertex's index in `layer`, by identity: a `Vertex` hashed by
        # value would walk its `up`/`down` neighbours forever.
        def positions(layer)
          index = {}.compare_by_identity
          layer.each_with_index { |v, i| index[v] = i }
          index
        end

        def crossings(layers)
          layers.each_cons(2).sum do |upper, lower|
            upper_pos = positions(upper)
            lower_pos = positions(lower)
            segments = upper.flat_map { |v| v.down.map { |w| [upper_pos[v], lower_pos[w]] } }
            segments.combination(2).count { |(a1, b1), (a2, b2)| ((a1 - a2) * (b1 - b2)).negative? }
          end
        end

        def place(group, vertices, layers, edges, rank_of, direction)
          main_pos = rank_positions(group, layers, edges, rank_of)
          cross_pos = cross_positions(layers)

          vertices.each_value do |v|
            box = @boxes[v.node.id]
            cross = cross_pos[v]
            main = main_pos[v.rank]
            box.x, box.y = direction == :down ? [cross, main] : [main, cross]
          end
        end

        # Each rank's center along the main axis: as thick as its thickest
        # node, `rank_gap` from the next -- or more, where a labeled edge
        # crosses that gap.
        def rank_positions(group, layers, edges, rank_of)
          thickness = layers.map { |layer| layer.map(&:main).max || 0.0 }
          base_gap = group.gap(@theme.rank_edge_label_gap)
          labeled = edges.select { |_, _, l| l }.map { |a, b, _| rank_of[a.id]...rank_of[b.id] }
          positions = [thickness.first / 2.0]
          (1...layers.length).each do |r|
            gap = labeled.any? { |span| span.cover?(r - 1) } ? [base_gap, @theme.rank_edge_label_gap * 1.5].max : base_gap
            positions << (positions.last + (thickness[r - 1] / 2.0) + gap + (thickness[r] / 2.0))
          end
          positions
        end

        # Packs each rank, then pulls every vertex toward the mean of its
        # neighbours in the adjacent ranks, alternating which side it
        # listens to -- each rank re-packed around those targets without
        # ever breaking its order or its minimum gaps.
        def cross_positions(layers)
          pos = {}.compare_by_identity
          layers.each do |layer|
            cursor = 0.0
            layer.each_with_index do |v, i|
              cursor += separation(layer[i - 1], v) if i.positive?
              pos[v] = cursor
            end
          end

          ALIGN_PASSES.times do |pass|
            ranks = pass.even? ? (1...layers.length) : (0...(layers.length - 1)).reverse_each
            ranks.each do |r|
              side = pass.even? ? :up : :down
              targets = layers[r].map { |v| (ns = v.send(side)).empty? ? pos[v] : ns.sum { |n| pos[n] } / ns.length.to_f }
              repack(layers[r], targets).each_with_index { |x, i| pos[layers[r][i]] = x }
            end
          end

          center = (pos.values.min + pos.values.max) / 2.0
          pos.transform_values { |x| x - center }
        end

        # The positions closest to `targets` that keep `layer`'s order and
        # gaps: the mean of the tightest left-to-right and right-to-left
        # packings around them -- each keeps every gap, so their mean does.
        def repack(layer, targets)
          n = layer.length
          left = Array.new(n)
          right = Array.new(n)
          n.times do |i|
            left[i] = i.zero? ? targets[i] : [targets[i], left[i - 1] + separation(layer[i - 1], layer[i])].max
          end
          (n - 1).downto(0) do |i|
            right[i] = i == n - 1 ? targets[i] : [targets[i], right[i + 1] - separation(layer[i], layer[i + 1])].min
          end
          left.zip(right).map { |l, r| (l + r) / 2.0 }
        end

        # How far apart two neighbouring vertices' centers must be: half of
        # each one's cross size, plus a sibling gap -- only half one next
        # to a dummy's lane, which is its own spacing already.
        def separation(a, b)
          gap = a.dummy? || b.dummy? ? @theme.sibling_gap / 2.0 : @theme.sibling_gap
          (a.cross / 2.0) + gap + (b.cross / 2.0)
        end
      end
    end
  end
end
