# frozen_string_literal: true

module Archsight
  module Diagram
    class Layout
      # Post-hoc x-alignment of connected top-level root components, and
      # the "hidden stack" width-equalization pass over roots.
      class RootAlignment
        def initialize(graph, boxes, rank_topology:, overlap_resolver:, theme:)
          @graph = graph
          @theme = theme
          @boxes = boxes
          @rank_topology = rank_topology
          @overlap_resolver = overlap_resolver
        end

        # A "hidden stack": top-level roots read top-to-bottom just like a
        # stack's ranks, but without an explicit `stack` wrapping them (and
        # therefore no rendered box/label for it) — so give them the same
        # "use the available width" treatment a stack's direct children get,
        # purely as a layout pass over the roots that already exist.
        def expand_roots_to_common_width
          return if @graph.roots.length < 2

          expander = Expander.new(@boxes, theme: @theme)
          max_width = @graph.roots.map { |r| @boxes[r.id].width }.max
          @graph.roots.each { |r| expander.expand(r, Axis::WIDTH, max_width, inherited: r.extend?(false)) }
        end

        # `ForceSimulation#apply_align` only pulls a *pair* of connected
        # roots toward a shared x-center, as a weak spring alongside
        # repulsion/gravity/flow — with 3+ roots chained together (e.g. an
        # internet boundary -> a tiers stack -> an external-provider boundary)
        # it approximately converges but leaves a visible residual offset,
        # since no single pair's spring can perfectly satisfy the whole
        # chain at once. This deterministically finishes the job: every
        # connected component of roots (via any edge between them, direct or
        # through their descendants) ends up sharing one exact x-center.
        #
        # This is safe for the common case this targets — a simple top-to-
        # bottom chain, already well y-separated by `apply_flow` — but a
        # component that isn't a chain (e.g. roots connected in a cycle,
        # deliberately spread in 2D by `ForceSimulation#arrange` to avoid
        # overlapping) would collapse onto one x if left there, so
        # `resolve_overlaps` runs right after to push anything back apart
        # that this reintroduced.
        def align_connected_roots
          connected_root_components.each do |component|
            next if component.length < 2

            target_x = component.sum { |r| @boxes[r.id].x } / component.length.to_f
            component.each { |r| @boxes[r.id].x = target_x }

            @overlap_resolver.resolve_overlaps(component, label_gaps: @rank_topology.label_gap_requirements(TopLevel, component))
          end
        end

        private

        def connected_root_components
          adjacency = Hash.new { |h, k| h[k] = [] }
          @graph.roots.each { |r| adjacency[r] } # ensure roots with no edges still appear

          @rank_topology.attraction_edges.each do |e|
            ra = @rank_topology.representative_in(TopLevel, e.from)
            rb = @rank_topology.representative_in(TopLevel, e.to)
            next unless ra && rb && !ra.equal?(rb)

            adjacency[ra] << rb
            adjacency[rb] << ra
          end

          visited = {}
          components = []

          @graph.roots.each do |root|
            next if visited[root.id]

            component = []
            queue = [root]
            until queue.empty?
              node = queue.shift
              next if visited[node.id]

              visited[node.id] = true
              component << node
              queue.concat(adjacency[node])
            end
            components << component
          end

          components
        end
      end
    end
  end
end
