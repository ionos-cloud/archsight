# frozen_string_literal: true

require_relative "graph"
require_relative "support/axis"
require_relative "support/text_metrics"
require_relative "style/theme"
require_relative "style/representers"
require_relative "routing/edge_router/attachment"
require_relative "layout/top_level"
require_relative "layout/stacker"
require_relative "layout/expander"
require_relative "layout/rank_topology"
require_relative "layout/overlap_resolver"
require_relative "layout/force_simulation"
require_relative "layout/ranked_arranger"
require_relative "layout/rank_arranger"
require_relative "layout/root_alignment"
require_relative "layout/globalizer"
require_relative "legend"

module Archsight
  module Diagram
    # Compound force-directed layout: each group is laid out independently
    # (Fruchterman-Reingold style simulation over its direct children), then
    # becomes a sized box inside its own parent's simulation. Edges that cross
    # group boundaries are mapped, at each level, to an attractive force
    # between the ancestor boxes that are direct children of the group being
    # laid out, so connected subsystems are still pulled toward each other.
    class Layout
      Box = Struct.new(:x, :y, :width, :height) do
        # `left`/`right`/`top`/`bottom` fall through to a live computation
        # until `freeze_bounds!` runs -- every read during `Layout.compute`
        # itself (including ones on a box whose position/size isn't final
        # yet, e.g. `fit_group_and_normalize_children`) stays correct.
        # `Layout#compute` calls `freeze_bounds!` on
        # every box once, after its own last mutation, so the render/routing
        # pipeline's much larger volume of reads (these are never mutated
        # again after `Layout.compute` returns) hit a cached value instead
        # of recomputing a division every time.
        def left = @left || (x - (width / 2.0))
        def right = @right || (x + (width / 2.0))
        def top = @top || (y - (height / 2.0))
        def bottom = @bottom || (y + (height / 2.0))

        def freeze_bounds!
          @left = x - (width / 2.0)
          @right = x + (width / 2.0)
          @top = y - (height / 2.0)
          @bottom = y + (height / 2.0)
        end

        # Which of this box's sides `point` sits on (see
        # `EdgeRouter::Attachment.side_of`), or nil.
        def side_of(point) = EdgeRouter::Attachment.side_of(self, point)

        # Signed "how much would `self` and `other` need to move apart
        # (along `axis`) to have exactly `gap` between them" -- positive
        # means they currently overlap by that much, zero or negative means
        # they're already at least `gap` apart. Two 1D intervals centered at
        # `axis.position` with size `axis.size` overlap iff the distance
        # between their centers is less than half the sum of their sizes.
        def overlap_on(axis, other, gap: 0.0)
          ((axis.size(self) + axis.size(other)) / 2.0) + gap - (axis.position(self) - axis.position(other)).abs
        end

        def overlaps_x?(other) = overlap_on(Axis::WIDTH, other).positive?
        def overlaps_y?(other) = overlap_on(Axis::HEIGHT, other).positive?
      end

      # `theme` travels with the layout so the renderer draws with the same
      # font sizes/title offsets the boxes were sized for; `legend` (a
      # `Legend::Placement`, or nil for none) is where the legend went --
      # its boxes are in `boxes` like any node's.
      Result = Struct.new(:boxes, :width, :height, :theme, :legend, keyword_init: true) do
        def initialize(theme: Theme::DEFAULT, **) = super
      end

      # Pairs a Graph::Node with its computed Box, for the routing stages
      # that read a node's box and its shape together
      # (`EdgeRouting#positioned`, `DataflowRouting#positioned`) -- most
      # of the layout engine never needs to know a node's kind/attrs, only
      # its box.
      PositionedNode = Struct.new(:node, :box) do
        def shape = node.shape
      end

      # `legend` (one of `Legend::MODES`) overrides the source's own
      # `legend "..."` statement; `relation_filter` is which relations the
      # renderer will draw, so the legend explains exactly those.
      def self.compute(graph, theme: Theme::DEFAULT, legend: nil, relation_filter: Relations::DEFAULT_FILTER)
        new(graph, theme: theme, legend: legend, relation_filter: relation_filter).compute
      end

      # `result` with a legend placed beside its (already positioned) boxes,
      # exactly as `compute` would place it -- for a layout arrived at some
      # other way than `compute`, e.g. boxes positioned by hand.
      def self.attach_legend(graph, result, legend: nil, relation_filter: Relations::DEFAULT_FILTER)
        new(graph, theme: result.theme, legend: legend, relation_filter: relation_filter, boxes: result.boxes.dup).attach_legend(result)
      end

      def initialize(graph, theme: Theme::DEFAULT, legend: nil, relation_filter: Relations::DEFAULT_FILTER, boxes: {})
        @graph = graph
        @theme = theme
        @legend_mode = legend || graph.legend_mode || Legend::DEFAULT_MODE
        @relation_filter = relation_filter
        @boxes = boxes
        @rank_topology = RankTopology.new(@graph, @boxes, theme: theme)
        @overlap_resolver = OverlapResolver.new(@boxes, theme: theme)
        @force_simulation = ForceSimulation.new(@boxes, rank_topology: @rank_topology, overlap_resolver: @overlap_resolver,
                                                        theme: theme)
        ranked_arranger = RankedArranger.new(@graph, @boxes, rank_topology: @rank_topology, theme: theme)
        @rank_arranger = RankArranger.new(@boxes, rank_topology: @rank_topology, force_simulation: @force_simulation,
                                                  ranked_arranger: ranked_arranger, theme: theme, top_level_ranks: graph.ranks_mode)
        @root_alignment = RootAlignment.new(@graph, @boxes, rank_topology: @rank_topology, overlap_resolver: @overlap_resolver,
                                                            theme: theme)
        @globalizer = Globalizer.new(@boxes, rank_topology: @rank_topology, theme: theme, ranked: @rank_arranger.ranked)
      end

      def compute
        @graph.roots.each { |n| size_and_place(n) }
        @rank_arranger.arrange_children(TopLevel, @graph.roots)
        # Ranked roots are already arranged exactly where their ranks put
        # them -- re-centering or re-widening them would undo that.
        unless @rank_arranger.ranked[TopLevel]
          @root_alignment.expand_roots_to_common_width
          @root_alignment.align_connected_roots
        end
        @globalizer.globalize_all(@graph.roots)
        legend = place_legend
        normalize_to_canvas
        @boxes.each_value(&:freeze_bounds!)
        Result.new(boxes: @boxes, width: @canvas_width, height: @canvas_height, theme: @theme, legend: legend)
      end

      # See `Layout.attach_legend`: the canvas only ever grows to take the
      # legend in, and `result`'s own boxes stay exactly where they were.
      def attach_legend(result)
        legend = place_legend
        return result unless legend

        legend.nodes.each { |n| @boxes[n.id].freeze_bounds! }
        frame = @boxes[legend.frame.id]
        width = [result.width, frame.right + @theme.canvas_margin].max
        height = [result.height, frame.bottom + @theme.canvas_margin].max
        Result.new(boxes: @boxes, width: width, height: height, theme: @theme, legend: legend)
      end

      private

      # Bottom-up: determine width/height for every node, and (for groups)
      # position children relative to the group's own local origin (0, 0).
      def size_and_place(node)
        if node.leaf?
          w, h = leaf_size(node)
        else
          node.children.each { |c| size_and_place(c) }
          @rank_arranger.arrange_children(node, node.children)
          w, h = fit_group_and_normalize_children(node)
        end
        @boxes[node.id] = Box.new(0.0, 0.0, w, h)
      end

      def leaf_size(node)
        return node.layout_size if node.legend_entry?

        longest = TextMetrics.longest_line_length(node.label)
        extra_height = TextMetrics.extra_height(node.label, line_height: @theme.label_line_height)

        if node.shape == "actor"
          width = [longest * @theme.char_width * 0.7, @theme.actor_min_width].max
          return [width, @theme.actor_figure_height + @theme.actor_label_height + extra_height]
        end

        width = [label_width(node) + @theme.node_label_padding, @theme.node_min_width].max
        [width, @theme.node_height + extra_height]
      end

      def label_width(node)
        return TextMetrics.rendered_width(node.label, font_size: @theme.node_font_size) if @theme.measure_text_with_font_metrics

        TextMetrics.longest_line_length(node.label) * @theme.char_width
      end

      # Shifts children so their bounding box starts at (padding, padding +
      # title height), i.e. relative to the group's own local top-left corner.
      # Returns the group's own [width, height].
      # An anonymous `layer`/`stack` (declared with no id) reserves no
      # padding or title space of its own, since it never renders a box —
      # its size is exactly its children's tight bounding box, so it acts
      # as a pure layout hint rather than an extra visible nesting level
      # (see `Graph::Node#layout_padding`).
      def fit_group_and_normalize_children(node)
        children = node.children
        return [0.0, 0.0] if children.empty? && node.anonymous?
        return [@theme.node_min_width, @theme.title_height + @theme.padding] if children.empty?

        padding = node.layout_padding(@theme)
        title = node.layout_title_height(@theme)

        min_x = children.map { |c| @boxes[c.id].left }.min
        max_x = children.map { |c| @boxes[c.id].right }.max
        min_y = children.map { |c| @boxes[c.id].top }.min
        max_y = children.map { |c| @boxes[c.id].bottom }.max

        shift_x = padding - min_x
        shift_y = padding + title - min_y

        children.each do |c|
          b = @boxes[c.id]
          b.x += shift_x
          b.y += shift_y
        end

        width = (max_x - min_x) + (2 * padding)
        height = (max_y - min_y) + title + (2 * padding)
        [width, height]
      end

      # The legend (see `Legend`), laid out as its own little tree by the
      # same `size_and_place` as everything else, then put beside the
      # diagram already laid out -- the way a `stack`/`layer` would stack
      # the two, but without actually wrapping the diagram's roots in one,
      # which would swap their own top-level arrangement (a force
      # simulation, then `RootAlignment`) for a plain pack. Returns nil for
      # no legend.
      def place_legend
        return nil if @legend_mode == "none"

        rows = Legend.rows(@graph, relation_filter: @relation_filter)
        return nil if rows.empty?

        main = extent(@boxes.values)
        side = @legend_mode
        side = main[:height] > main[:width] ? "right" : "bottom" if side == "auto"
        frame = legend_frame(rows, side, main)

        box = @boxes[frame.id]
        box.x = %w[left right].include?(side) ? beside(side, main, box.width) : main[:left] + (box.width / 2.0)
        box.y = %w[top bottom].include?(side) ? beside(side, main, box.height) : main[:top] + (box.height / 2.0)
        @globalizer.globalize_all([frame])
        Legend::Placement.new(frame: frame, side: side)
      end

      # The legend with as many columns as fit the diagram's width (below or
      # above it), or as few as fit its height (beside it) -- each column
      # only as wide as its own widest row, so it's worth trying each count
      # rather than guessing from the single widest row.
      def legend_frame(rows, side, main)
        horizontal = %w[top bottom].include?(side)
        columns = horizontal ? 1 : rows.length

        (1..rows.length).each do |n|
          frame = Legend.tree(rows, columns: n)
          size_and_place(frame)
          box = @boxes[frame.id]
          forget(frame)

          if horizontal
            break if n > 1 && box.width > main[:width]

            columns = n
          elsif box.height <= main[:height]
            columns = n
            break
          end
        end

        frame = Legend.tree(rows, columns: columns)
        size_and_place(frame)
        frame
      end

      # The center coordinate, on `side`'s own axis, of a legend `size`
      # long placed `Legend::GAP` beyond the diagram's `main` extent.
      def beside(side, main, size)
        case side
        when "right" then main[:right] + Legend::GAP + (size / 2.0)
        when "left" then main[:left] - Legend::GAP - (size / 2.0)
        when "bottom" then main[:bottom] + Legend::GAP + (size / 2.0)
        else main[:top] - Legend::GAP - (size / 2.0)
        end
      end

      def forget(node)
        @boxes.delete(node.id)
        node.children.each { |c| forget(c) }
      end

      def extent(boxes)
        left = boxes.map(&:left).min || 0.0
        right = boxes.map(&:right).max || 0.0
        top = boxes.map(&:top).min || 0.0
        bottom = boxes.map(&:bottom).max || 0.0
        { left: left, right: right, top: top, bottom: bottom, width: right - left, height: bottom - top }
      end

      def normalize_to_canvas
        all = @boxes.values
        min_x = all.map(&:left).min || 0.0
        min_y = all.map(&:top).min || 0.0
        max_x = all.map(&:right).max || 0.0
        max_y = all.map(&:bottom).max || 0.0

        shift_x = @theme.canvas_margin - min_x
        shift_y = @theme.canvas_margin - min_y

        all.each do |b|
          b.x += shift_x
          b.y += shift_y
        end

        @canvas_width = (max_x - min_x) + (2 * @theme.canvas_margin)
        @canvas_height = (max_y - min_y) + (2 * @theme.canvas_margin)
      end
    end
  end
end
