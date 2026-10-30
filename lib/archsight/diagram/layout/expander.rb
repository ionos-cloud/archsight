# frozen_string_literal: true

require_relative "../support/axis"

module Archsight
  module Diagram
    class Layout
      # Axis-aware size equalization: grows a node's box to a target size,
      # cascading into a single-child wrapper chain (e.g. a `boundary`
      # around one `layer`) so the whole chain spans the same size instead
      # of only the outermost box growing while the rest float, recentered
      # but still their old, narrower size, inside it.
      #
      # Used both visibly (a `stack`'s ranks all matching its widest one)
      # and invisibly (`Layout#compute` running it over top-level roots, as
      # a "hidden stack" with no rendered container of its own).
      class Expander
        def initialize(boxes, theme:)
          @boxes = boxes
          @theme = theme
        end

        # Grows `node`'s box to `target_size` along `axis` (:width or
        # :height). No-op if it's already at least that size. Containers
        # with more than one child stop after recentering that group as a
        # whole by default: there's no unambiguous way to redistribute the
        # extra space among several children -- unless `extend` is in
        # effect for this node, in which case `stretch_children` (or, on
        # the cross axis, a full per-child expand) grows each of them too.
        #
        # `extend` is inherited down the cascade: `inherited` is whatever
        # the nearest ancestor that set it decided, and `node`'s own
        # `extend` attr (if present) overrides that inherited value for
        # this node *and everything below it*, until some deeper
        # descendant's own `extend` attr overrides it again -- so a single
        # `extend "true"` near the top applies all the way down until a
        # `extend "false"` opts a subtree back out.
        def expand(node, axis, target_size, inherited: false)
          box = @boxes[node.id]
          current = axis.size(box)

          if node.leaf?
            # A leaf is only resized on an axis its representer can actually
            # absorb without visibly distorting -- see each Representer's
            # own `stretchable?` for why (a circle/actor's proportions are
            # tied to its box size in ways that break if stretched to match
            # an unrelated, much larger sibling).
            return if target_size <= current
            return unless node.representer.stretchable?

            axis.set_size(box, target_size)
            return
          end

          extend = node.extend?(inherited)

          # `node`'s own box may already be at least `target_size` (e.g. it
          # naturally sized itself, bottom-up, to fit an already-wide
          # descendant elsewhere in its subtree) even though an
          # extend-opted descendant *inside* it -- possibly several levels
          # down a single-child wrapper chain -- still hasn't been visited
          # by this top-down cascade yet. So once `extend` is active, the
          # cascade must keep descending regardless of whether *this* node
          # has any `extra` to grow by; `own_target` is what actually gets
          # applied/passed down (never shrinks `node`, but doesn't force it
          # wider than it needs to be just to satisfy a smaller
          # `target_size` either).
          own_target = [target_size, current].max
          extra = own_target - current
          return if extra <= 0 && !extend

          axis.set_size(box, own_target) if extra.positive?

          # `extend`'s multi-child stretching only kicks in for a ranked
          # node (`stack`/`layer`): both use `Stacker#pack`'s "every child's
          # cross-axis coordinate sits at half the shared width/height"
          # convention (relied on directly below), which is what makes it
          # safe to reposition children here at all. `group`/`boundary`
          # content is force-simulated in both dimensions with no such
          # convention, so `extend` is inert for them (their `main_axis` is
          # `nil`) -- they always fall through to the plain recenter below.
          if node.children.length > 1 && (extend || (node.extend_width? && axis == Axis::WIDTH)) && node.ranked?
            if axis == node.main_axis
              stretch_children(node, axis, extra, extend)
            else
              # The children don't compete for room on this axis -- a
              # `stack`'s ranks (or a `layer`'s shared centerline) already
              # each span its own full breadth on their cross axis, same as
              # every other rank/peer, so each one independently gets the
              # *whole* new target size, not a split share of it. Growing a
              # child alone isn't enough, though: `Stacker#pack` positions
              # every child's cross-axis coordinate at exactly half the
              # shared width/height (e.g. a stack's `box.x = max_width /
              # 2.0` for every rank, regardless of that rank's own width),
              # so growing this axis without also moving each child back to
              # the *new* half-point leaves them off-center relative to
              # their own (now wider) box -- explaining a rank that visibly
              # spills outside its container despite matching its siblings'
              # width exactly.
              #
              # The room they get is the *inner* one -- the target minus the
              # node's own padding (and title bar), as in the single-child
              # case below -- or they would sit flush on its border; the
              # centerline is the middle of that inner area.
              inner = own_target - inset(node, axis)
              center = leading_inset(node, axis) + (inner / 2.0)
              node.children.each do |c|
                expand(c, axis, inner, inherited: extend)
                axis.set_position(@boxes[c.id], center)
              end
            end
            return
          end

          recenter_children(node, axis, node.anchor_shift(axis, extra, default: :center)) if extra.positive?

          return unless node.children.length == 1

          expand(node.children.first, axis, own_target - inset(node, axis), inherited: extend)
        end

        # `extend "height"`: grows `node` to `target` height keeping its
        # content top-aligned (or at its `anchor`), then hands the extra room to whatever inside
        # can absorb it -- a `stack` child carrying `extend "height"`
        # itself (the first such one in a stack's column gets all of it, and
        # the ranks below it move down, so e.g. a footer rank lines up
        # across columns), reached through single-child wrappers such as a
        # `boundary` around a `stack`.
        def grow_height(node, target)
          box = @boxes[node.id]
          extra = target - box.height
          return if extra <= 0

          box.height = target
          return if node.children.empty?

          # Room goes to whatever inside takes it (an `extend "height"` child
          # of a stack/layer, possibly behind a wrapper); only when nothing
          # does, the content sits at the node's `anchor` (default: top).
          unless absorbs?(node)
            delta = node.anchor_shift(Axis::HEIGHT, extra, default: :top)
            return recenter_children(node, Axis::HEIGHT, delta) if delta.positive?
          end

          if node.layer?
            fill_layer(node, extra)
          elsif node.children.length == 1
            inner = node.children.first
            grow_top_aligned(inner, extra) if inner.extend_height? || absorbs?(inner)
          elsif node.stack?
            absorb_in_stack(node, extra)
          end
        end

        private

        # True if growing `node` by `extend "height"` hands the extra room to
        # something inside it (see `grow_height`).
        def absorbs?(node)
          return false if node.leaf? || node.children.empty?
          return node.children.any?(&:extend_height?) if node.layer? || node.stack?

          node.children.length == 1 && (node.children.first.extend_height? || absorbs?(node.children.first))
        end

        # A grown `layer`'s `extend "height"` children fill the new height
        # too (they were only matched to their tallest sibling before).
        def fill_layer(node, extra)
          room = @boxes[node.id].height - inset(node, Axis::HEIGHT)
          node.children.select(&:extend_height?).each do |c|
            grow = room - @boxes[c.id].height
            grow_top_aligned(c, grow) if grow.positive? && extra.positive?
          end
        end

        # Grows a child by `extra` keeping its top edge where it is (box
        # positions are centers, so the center moves down by half of it).
        def grow_top_aligned(node, extra)
          grow_height(node, @boxes[node.id].height + extra)
          @boxes[node.id].y += extra / 2.0
        end

        # Gives `extra` to the first child of the `stack` `node` marked
        # `extend "height"`, and shifts every later rank down by it.
        def absorb_in_stack(node, extra)
          ordered = node.children.sort_by { |c| @boxes[c.id].y }
          index = ordered.index(&:extend_height?)
          return unless index

          grower = ordered[index]
          grow_top_aligned(grower, extra)
          ordered[(index + 1)..].each { |c| @boxes[c.id].y += extra }
        end

        # How much of a container's size on `axis` is reserved by its own
        # padding (and, on the height axis, its title bar) rather than
        # available to a single child filling it -- the node's own
        # `layout_padding`/`layout_title_height` (nothing, for an anonymous
        # `layer`/`stack`, since it renders no box to pad).
        # The padding (plus title bar, on the height axis) before the content.
        def leading_inset(node, axis)
          padding = node.layout_padding(@theme)
          axis == Axis::HEIGHT ? padding + node.layout_title_height(@theme) : padding
        end

        def inset(node, axis)
          padding = 2 * node.layout_padding(@theme)
          axis == Axis::HEIGHT ? padding + node.layout_title_height(@theme) : padding
        end

        # Shifts `node`'s direct children by `delta` along `axis` (still in
        # `node`'s own local coordinate frame at this point). Each child's
        # own descendants are positioned relative to it, so shifting only
        # the direct children carries the whole subtree along correctly.
        def recenter_children(node, axis, delta)
          node.children.each do |c|
            box = @boxes[c.id]
            axis.set_position(box, axis.position(box) + delta)
          end
        end

        # Opt-in alternative to `recenter_children` for a container with
        # more than one child (an `extend` attr, e.g. a `layer` of two
        # peers that should each visibly widen instead of just floating,
        # newly padded, inside the group's now-wider box).
        #
        # `node`'s own box.x/y isn't a usable reference point here: at this
        # point in the pipeline (`expand` runs before the parent stack's own
        # `Stacker.pack`/`globalize`), it's still whatever
        # `size_and_place` initialized it to, unrelated to where `node`'s
        # *children* actually sit in its local frame. So instead of
        # recomputing positions from `node`'s box, this works purely in
        # relative terms, mirroring `recenter_children`'s own approach:
        # split `extra` evenly across the children, grow each by its share
        # (cascading through `expand`, so a stretch-opted or single-child
        # descendant keeps working too), then re-flow them from the first
        # child's own *original* leading edge, preserving each pair's
        # original gap exactly -- since the re-flowed row's total span
        # grows by exactly `extra` (the per-child shares sum to it) while
        # anchored at the *original*, unshifted start, this alone already
        # leaves the row symmetrically centered under the container's own
        # (equally) grown box; no separate recentering shift is needed (and
        # applying one on top would double-shift it).
        def stretch_children(node, axis, extra, extend)
          ordered = node.children.sort_by { |c| axis.position(@boxes[c.id]) }
          gaps = ordered.each_cons(2).map { |a, b| gap_between(a, b, axis) }
          leading_edge = axis.leading_edge(@boxes[ordered.first.id])

          share = extra / ordered.length.to_f
          ordered.each do |c|
            current = axis.size(@boxes[c.id])
            expand(c, axis, current + share, inherited: extend)
          end

          pos = leading_edge
          ordered.each_with_index do |c, i|
            box = @boxes[c.id]
            size = axis.size(box)
            axis.set_position(box, pos + (size / 2.0))
            pos += size + (gaps[i] || 0.0)
          end
        end

        def gap_between(a, b, axis)
          axis.leading_edge(@boxes[b.id]) - axis.trailing_edge(@boxes[a.id])
        end
      end
    end
  end
end
