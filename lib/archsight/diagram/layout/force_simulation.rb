# frozen_string_literal: true

require_relative "../style/relations"

module Archsight
  module Diagram
    class Layout
      # The Fruchterman-Reingold-style force-directed engine used for
      # `:group`/`:boundary` children and top-level roots -- `:layer`/
      # `:stack` children are deterministically ranked instead (see
      # `RankArranger`).
      class ForceSimulation
        GRAVITY = 0.1
        FLOW_STRENGTH = 0.9
        ITERATIONS = 300

        def initialize(boxes, rank_topology:, overlap_resolver:, theme:)
          @boxes = boxes
          @theme = theme
          @rank_topology = rank_topology
          @overlap_resolver = overlap_resolver
        end

        # Runs a force-directed simulation positioning `children` (siblings
        # under `group`, or top-level roots when `group` is `TopLevel`),
        # then resolves any remaining rectangle overlaps.
        def arrange(group, children)
          return if children.empty?

          if children.length == 1
            @boxes[children.first.id].x = 0.0
            @boxes[children.first.id].y = 0.0
            return
          end

          children.each_with_index { |c, i| initialize_position(c, i, children.length) }

          edges = @rank_topology.relevant_edges(group, children)
          avg_area = children.sum { |c| @boxes[c.id].width * @boxes[c.id].height } / children.length.to_f
          k = Math.sqrt(avg_area) * 1.3
          initial_temp = k * 2.0

          ITERATIONS.times do |iter|
            temp = initial_temp * (1.0 - (iter.to_f / ITERATIONS))
            disp = Hash.new { |h, key| h[key] = [0.0, 0.0] }

            children.each do |a|
              children.each do |b|
                next if a.equal?(b)

                apply_repulsion(disp, a, b, k)
              end
            end

            edges.each { |a, b, _rel| apply_attraction(disp, a, b, k) }
            edges.each { |a, b, rel| apply_flow(disp, *flow_endpoints(a, b, rel), k) }
            edges.each { |a, b, _rel| apply_align(disp, a, b) } if group.top_level?

            children.each { |c| apply_gravity(disp, c) }

            children.each do |c|
              dx, dy = disp[c.id]
              dist = Math.sqrt((dx * dx) + (dy * dy))
              dist = 0.01 if dist < 0.01
              limited = [dist, temp].min
              box = @boxes[c.id]
              box.x += (dx / dist) * limited
              box.y += (dy / dist) * limited
            end
          end

          @overlap_resolver.resolve_overlaps(children, label_gaps: @rank_topology.label_gap_requirements(group, children),
                                                       default_gap: group.gap(@theme.sibling_gap))
        end

        private

        def initialize_position(node, index, total)
          box = @boxes[node.id]
          radius = 100.0 + (total * 10.0)
          angle = total <= 1 ? 0.0 : (2 * Math::PI * index / total)
          box.x = Math.cos(angle) * radius
          box.y = Math.sin(angle) * radius
        end

        def apply_repulsion(disp, a, b, k)
          ba = @boxes[a.id]
          bb = @boxes[b.id]
          dx = ba.x - bb.x
          dy = ba.y - bb.y
          dist = Math.sqrt((dx * dx) + (dy * dy))
          dist = 0.01 if dist < 0.01
          force = (k * k) / dist
          disp[a.id][0] += (dx / dist) * force
          disp[a.id][1] += (dy / dist) * force
        end

        # A weak pull toward the local origin (0, 0). Without this, a set of
        # siblings with no edges between them (e.g. alternative drivers that
        # don't talk to each other) has nothing but repulsion acting on it and
        # drifts apart without bound over the simulation's iterations.
        def apply_gravity(disp, node)
          box = @boxes[node.id]
          disp[node.id][0] -= box.x * GRAVITY
          disp[node.id][1] -= box.y * GRAVITY
        end

        def apply_attraction(disp, a, b, k)
          ba = @boxes[a.id]
          bb = @boxes[b.id]
          dx = ba.x - bb.x
          dy = ba.y - bb.y
          dist = Math.sqrt((dx * dx) + (dy * dy))
          dist = 0.01 if dist < 0.01
          force = (dist * dist) / k
          disp[a.id][0] -= (dx / dist) * force
          disp[a.id][1] -= (dy / dist) * force
          disp[b.id][0] += (dx / dist) * force
          disp[b.id][1] += (dy / dist) * force
        end

        # Biases `a` (the edge's source) to sit above `b` (its target) by at
        # least a modest margin, so the whole diagram reads top-to-bottom
        # along the direction of its connections instead of settling into
        # whatever orientation the undirected repulsion/attraction forces
        # happen to reach. Inactive once that minimum separation already
        # holds, so it only breaks ties/orientation rather than fighting the
        # other forces once the flow direction is satisfied.
        def apply_flow(disp, a, b, k)
          ba = @boxes[a.id]
          bb = @boxes[b.id]
          shortfall = (k * 0.5) - (bb.y - ba.y)
          return unless shortfall.positive?

          push = shortfall * FLOW_STRENGTH
          disp[a.id][1] -= push
          disp[b.id][1] += push
        end

        # For an `inverted_flow?` relation (`implements`), `apply_flow`
        # should treat it as if it ran target -> source instead of source ->
        # target -- only for the flow bias; the rendered arrow is untouched.
        def flow_endpoints(a, b, relation)
          Relations.for(relation).inverted_flow? ? [b, a] : [a, b]
        end

        # Top-level-only: pulls a connected pair of roots toward sharing an
        # x-center. Nothing else provides this — repulsion/attraction pull
        # along whatever diagonal the nodes happen to be on, and `apply_flow`
        # only constrains their vertical separation — so without it, two
        # roots connected by a single edge (e.g. an application above the
        # stack it calls into) settle at an arbitrary horizontal offset
        # instead of reading as directly above/below each other. Scoped to
        # the top level since nested groups already have their own tuned
        # horizontal placement (e.g. external-alignment mirroring).
        def apply_align(disp, a, b, strength: 0.15)
          ba = @boxes[a.id]
          bb = @boxes[b.id]
          push = (bb.x - ba.x) * strength
          disp[a.id][0] += push
          disp[b.id][0] -= push
        end
      end
    end
  end
end
