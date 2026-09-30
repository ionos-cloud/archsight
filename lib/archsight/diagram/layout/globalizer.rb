# frozen_string_literal: true

module Archsight
  module Diagram
    class Layout
      # Top-down local-to-absolute coordinate conversion, with
      # external-alignment mirroring before each group's children are
      # converted.
      class Globalizer
        # `ranked` holds the containers `RankArranger` ranked: never mirrored,
        # since that would reverse their ranks.
        def initialize(boxes, rank_topology:, theme:, ranked: {})
          @boxes = boxes
          @ranked = ranked
          @theme = theme
          @rank_topology = rank_topology
          @globalized = {}
        end

        def globalize_all(roots)
          roots.each { |n| @globalized[n.id] = true }
          roots.each { |n| globalize(n) }
        end

        private

        # Top-down: `node`'s own box is already in absolute canvas coordinates
        # (set by its parent). Before converting its children from group-local
        # coordinates to absolute coordinates, mirror them (see
        # `refine_internal_arrangement`) when that better aligns a child with
        # an already-globalized external neighbor it connects to.
        def globalize(node)
          return if node.leaf?

          refine_internal_arrangement(node)

          box = @boxes[node.id]
          origin_x = box.left
          origin_y = box.top

          node.children.each do |c|
            cb = @boxes[c.id]
            cb.x += origin_x
            cb.y += origin_y
            @globalized[c.id] = true
          end

          node.children.each { |c| globalize(c) }
        end

        # Reflects `group`'s already-computed internal arrangement horizontally
        # and/or vertically when doing so better aligns children with external
        # neighbors they connect to (e.g. a child wired to something on the
        # group's left ends up on the left side instead of at an arbitrary
        # position that might land it directly in the path of unrelated
        # edges). A reflection is a rigid transform of the existing layout, so
        # it can never change the group's already-fixed size or introduce new
        # overlaps among its children — unlike re-simulating with a bias
        # force, which could reorient the whole group and leave its
        # (already-fixed) box mis-sized for the new arrangement.
        def refine_internal_arrangement(group)
          # A stack's and a layer's declaration order is meaningful (top to
          # bottom, left to right -- and a `columns` table is a layer of
          # stacks read column by column), so neither is ever flipped.
          return if group.stack? || group.layer? || @ranked[group]

          children = group.children
          return if children.length < 2

          box = @boxes[group.id]
          forces = external_anchor_forces(group, children, box.left, box.top)
          return if forces.empty?

          reflect_axis(group, children, Axis::WIDTH) if flip_improves_alignment?(box, forces, Axis::WIDTH)
          return unless flip_improves_alignment?(box, forces, Axis::HEIGHT)

          reflect_axis(group, children, Axis::HEIGHT)
        end

        # True if mirroring the given axis would, on net, move children closer
        # to the direction their external forces pull them.
        def flip_improves_alignment?(box, forces, axis)
          center = axis.size(box) / 2.0
          score = forces.sum do |id, force|
            force_component = force[axis.index]
            position = axis.position(@boxes[id])
            force_component * (position - center)
          end
          score.negative?
        end

        # Mirrors children within the group's padded content band on the given
        # axis (e.g. width -> content_left + content_right - x). Since it
        # mirrors within the same band the children already fit in, every
        # child stays inside the group and no new overlaps are introduced.
        def reflect_axis(group, children, axis)
          box = @boxes[group.id]
          padding = group.layout_padding(@theme)
          title = group.layout_title_height(@theme)
          low = padding + (axis == Axis::HEIGHT ? title : 0.0)
          high = axis.size(box) - padding

          children.each do |c|
            cb = @boxes[c.id]
            axis.set_position(cb, low + high - axis.position(cb))
          end
        end

        # For each child, sums unit vectors pointing toward every already-
        # globalized node it connects to outside `group` (expressed in
        # `group`'s local coordinate frame), keyed by child id.
        def external_anchor_forces(group, children, origin_x, origin_y)
          forces = Hash.new { |h, k| h[k] = [0.0, 0.0] }

          @rank_topology.attraction_edges.each do |e|
            [[e.from, e.to], [e.to, e.from]].each do |inner, outer|
              ra = @rank_topology.representative_in(group, inner)
              next unless ra
              next unless children.any? { |c| c.equal?(ra) }
              next if @rank_topology.representative_in(group, outer) # outer is inside group too, not external
              next unless @globalized[outer.id]

              outer_box = @boxes[outer.id]
              local_x = outer_box.x - origin_x
              local_y = outer_box.y - origin_y

              ra_box = @boxes[ra.id]
              dx = local_x - ra_box.x
              dy = local_y - ra_box.y
              dist = Math.sqrt((dx * dx) + (dy * dy))
              dist = 0.01 if dist < 0.01

              forces[ra.id][0] += dx / dist
              forces[ra.id][1] += dy / dist
            end
          end

          forces
        end
      end
    end
  end
end
