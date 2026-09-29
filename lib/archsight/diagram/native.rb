# frozen_string_literal: true

module Archsight
  module Diagram
    # Optional C kernels (ext/archsight_diagram_native) for the edge-routing hot loops
    # -- `PathMetrics.crossing_count` over each edge's candidates,
    # `EdgeRouter.select_best` against sibling paths (dataflow routing),
    # `BridgePath`'s obstacle scans, `LabelPlacer`'s overlap counts, and
    # the whole `EdgeRouting#refine_line_overlap!` sweep, whose all-pairs
    # sibling scoring is quadratic in the edge count and dominates render
    # time on large diagrams.
    #
    # Each entry point packs its inputs into flat binary strings (points as
    # doubles, paths delimited by an int32 offsets table), makes a single
    # call into C, and unpacks a packed result -- so the Ruby/C boundary is
    # crossed once per call rather than once per segment pair.
    #
    # The kernels are exact ports of the Ruby code, down to its
    # Kahan-Babuska summation (see archsight_diagram_native.c), so rendering is
    # byte-identical either way. When the extension isn't built -- or
    # `ARCHSIGHT_DIAGRAM_NATIVE=0` is set -- every entry point returns nil and callers
    # run their own Ruby implementation, which stays the reference.
    module Native
      unless ENV["ARCHSIGHT_DIAGRAM_NATIVE"] == "0"
        begin
          # A development build (`rake compile`) copies the library next to
          # this file; an installed gem puts it on the extension load path.
          require_relative "archsight_diagram_native"
        rescue LoadError
          begin
            require "archsight/diagram/archsight_diagram_native"
          rescue LoadError
            nil
          end
        end
      end

      module_function

      def available?
        const_defined?(:Kernels, false)
      end

      # `PathMetrics.crossing_count(path, obstacles)` for every path in
      # `paths`, or nil when the kernels aren't available.
      def crossing_counts(paths, obstacles)
        return nil unless available?

        points, offsets = pack_paths(paths)
        Kernels.crossing_counts(points, offsets, *box_table(obstacles)).unpack("l*")
      end

      # `[crossing_counts(paths, obstacles), lengths, turns]` from one packing
      # of `paths` -- `EdgeRouter.score_candidates`'s three per-candidate
      # terms, each length exactly `Geometry.path_length` (Integer 0 for a
      # path with no segment, as Ruby's empty `sum`) and each turn count
      # exactly `Geometry.turn_count`. Nil when the kernels aren't
      # available, or for a non-Float coordinate (`Math.hypot` of Integers
      # is fine, but the crossing test isn't).
      def score_paths(paths, obstacles)
        return nil unless available? && all_float?(paths)

        points, offsets = pack_paths(paths)
        crossings = Kernels.crossing_counts(points, offsets, *box_table(obstacles)).unpack("l*")
        lengths = Kernels.path_lengths(points, offsets).unpack("d*")
        paths.each_with_index { |path, i| lengths[i] = 0 if path.length < 2 }
        [crossings, lengths, Kernels.path_turns(points, offsets).unpack("l*")]
      end

      # For every path in `paths`, whether it runs through `a`'s or `b`'s
      # interior -- `PathMetrics.enters_interior?(path, a) ||
      # PathMetrics.enters_interior?(path, b)` -- as one `crossing_counts`
      # call against the two boxes shrunk by `EDGE_EPSILON` (its bounding-box
      # prefilters are non-strict, so a nonzero count is exactly "some
      # segment crosses"). Nil when the kernels aren't available, or for a
      # non-Float coordinate (Ruby's Liang-Barsky would divide Integers).
      def interior_hits(paths, a, b)
        return nil unless available? && all_float?(paths)

        points, offsets = pack_paths(paths)
        Kernels.crossing_counts(points, offsets, pack_interiors([a, b]), NO_EXCLUSIONS).unpack("l*").map(&:positive?)
      end

      # `boxes` shrunk by `EDGE_EPSILON` on every side (`PathMetrics::Interior`),
      # in `pack_boxes`'s table format.
      def pack_interiors(boxes)
        e = EdgeRouter::PathMetrics::EDGE_EPSILON
        boxes.flat_map do |box|
          left = box.left + e
          top = box.top + e
          right = box.right - e
          bottom = box.bottom - e
          [left, top, right, bottom, (left + right) / 2.0, (top + bottom) / 2.0, right - left, bottom - top]
        end.pack("d*")
      end

      # `BridgePath.bridge_candidates`'s two obstacle scans in one call:
      # `[gap_left, gap_right, gap_top, gap_bottom, min_top, max_bottom,
      # min_left, max_right]` -- each exit side's smallest gap to a facing
      # obstacle (Infinity when none faces it), then the outermost bounds
      # of `a`, `b` and the obstacles between them. Nil when the kernels
      # aren't available.
      def bridge_scan(a, b, obstacles)
        return nil unless available?

        Kernels.bridge_scan(pack_boxes([a]), pack_boxes([b]), *box_table(obstacles)).unpack("d*")
      end

      # For each of `rects` (Hashes with :left/:top/:right/:bottom, as
      # `LabelPlacer.label_bbox` builds them): how many of `table`'s boxes
      # (`pack_boxes`) plus `placed`'s rectangles (`pack_rects`) it
      # intersects -- `LabelPlacer#label_overlap_score` per rectangle.
      def rect_overlap_counts(rects, table, placed)
        Kernels.rect_overlap_counts(pack_rects(rects), table, placed).unpack("l*")
      end

      # For each of `rects` (as `pack_rects` takes them): how many of
      # `packed_paths` (a `pack_paths` result) other than path index `own`
      # (-1 for none) have a segment crossing it --
      # `LabelPlacer#path_hit_count` per rectangle.
      def path_rect_hits(packed_paths, rects, own)
        Kernels.path_rect_hits(*packed_paths, pack_rects(rects), own).unpack("l*")
      end

      def pack_rects(rects)
        rects.flat_map { |r| [r[:left], r[:top], r[:right], r[:bottom]] }.pack("d*")
      end

      # Boxes as the kernels' table format: per box its cached bounds and
      # the center/size `Box#overlap_on` computes from. See
      # `ObstacleMap#excluding`, which packs its whole map once.
      def pack_boxes(boxes)
        boxes.flat_map { |b| [b.left, b.top, b.right, b.bottom, b.x, b.y, b.width, b.height] }.pack("d*")
      end

      # `[table, excluded]` for `obstacles`: an `ObstacleMap::Obstacles`
      # list's shared, prepacked table plus the indices it leaves out, or a
      # plain Array packed on the spot with nothing excluded.
      def box_table(obstacles)
        if obstacles.respond_to?(:native_table) && obstacles.native_table
          [obstacles.native_table, obstacles.native_excluded]
        else
          [pack_boxes(obstacles), NO_EXCLUSIONS]
        end
      end

      NO_EXCLUSIONS = "".b.freeze

      # `EdgeRouting#refine_line_overlap!` in one call, setting each
      # `edge_paths` entry's `points` to its chosen candidate. Returns nil
      # (having changed nothing) when the kernels aren't available or the
      # input falls outside what they reproduce exactly: a current route
      # that isn't one of its own `scored` candidates, or a coordinate that
      # isn't a Float (Ruby's `segments_cross?` would do Integer division).
      def refine_line_overlap!(edge_paths, rounds)
        return nil unless available?

        choices = initial_choices(edge_paths)
        return nil unless choices

        candidates = edge_paths.flat_map { |ep| ep.scored.map { |s| s[:path] } }
        return nil unless all_float?(candidates)

        points, offsets = pack_paths(candidates)
        edge_offsets = edge_paths.each_with_object([0]) { |ep, acc| acc << (acc.last + ep.scored.length) }
        scored = edge_paths.flat_map(&:scored)

        chosen = Kernels.refine(points, offsets, edge_offsets.pack("l*"),
                                scored.map { |s| s[:crossing] }.pack("l*"),
                                scored.map { |s| s[:length] }.pack("d*"),
                                choices.pack("l*"), rounds, refine_params).unpack("l*")

        edge_paths.each_with_index { |ep, i| ep.points = candidates[chosen[i]] }
        true
      end

      # `EdgeRouter.select_best(scored, sibling_paths:)` as the index of the
      # chosen `scored` entry, or nil to leave it to the Ruby code: when the
      # kernels aren't available, when there are no siblings (Ruby's
      # scoring is trivial then), or when the input falls outside what the
      # kernel reproduces exactly -- a non-Float coordinate, or an empty
      # sibling path (which Ruby's own scoring raises on).
      #
      # A `SiblingPaths` list (see `PackedPaths#followed_by`) only has its
      # unpacked tail checked and packed here; its prefix was packed once.
      def select_best(scored, sibling_paths)
        return nil if !available? || sibling_paths.empty? || scored.empty?

        candidates = scored.map { |s| s[:path] }
        return nil unless all_float?(candidates)

        packed_siblings = pack_siblings(sibling_paths)
        return nil unless packed_siblings

        points, offsets = pack_paths(candidates)
        sibling_points, sibling_offsets = packed_siblings
        Kernels.select_best(points, offsets, scored.map { |s| s[:crossing] }.pack("l*"),
                            scored.map { |s| s[:length] }.pack("d*"), sibling_points, sibling_offsets, refine_params)
      end

      # `[points, offsets]` for `sibling_paths`, or nil if one is empty or
      # has a non-Float coordinate.
      def pack_siblings(sibling_paths)
        if sibling_paths.is_a?(SiblingPaths) && sibling_paths.prefix.packed?
          rest = sibling_paths.rest
          return nil if rest.any?(&:empty?) || !all_float?(rest)

          sibling_paths.prefix.pack_with(rest)
        else
          return nil if sibling_paths.any?(&:empty?) || !all_float?(sibling_paths)

          pack_paths(sibling_paths)
        end
      end

      # Each edge's current route as a global index into every edge's
      # concatenated candidates, or nil if some route isn't one of them.
      def initial_choices(edge_paths)
        base = 0
        edge_paths.map do |ep|
          local = ep.scored.index { |s| s[:path].equal?(ep.points) }
          return nil unless local

          (base + local).tap { base += ep.scored.length }
        end
      end

      def all_float?(paths)
        paths.all? { |path| path.all? { |(x, y)| x.is_a?(Float) && y.is_a?(Float) } }
      end

      def pack_paths(paths)
        [paths.flatten.pack("d*"), path_offsets(paths).pack("l*")]
      end

      def path_offsets(paths, start = 0)
        paths.each_with_object([start]) { |path, acc| acc << (acc.last + path.length) }
      end

      # A fixed list of sibling paths packed once up front (when the kernels
      # are available and every path is non-empty and all-Float), so
      # repeated `select_best` calls against it plus a few more paths each
      # time -- `DataflowRouting`'s plain-edge siblings plus whichever
      # dataflow segments are routed so far -- only pack those few. The
      # paths must not be mutated afterwards; `DataflowRouting` never
      # touches the plain edges' points.
      class PackedPaths
        attr_reader :paths

        def initialize(paths)
          @paths = paths
          return unless Native.available? && paths.none?(&:empty?) && Native.all_float?(paths)

          @points = paths.flatten.pack("d*")
          @offsets = Native.path_offsets(paths)
        end

        def packed? = !@points.nil?

        # `paths + rest`, carrying this prefix along for `Native.select_best`.
        def followed_by(rest) = SiblingPaths.new(self, rest)

        # `[points, offsets]` for `paths + rest`, packing only `rest` -- at
        # call time, so it reads `rest`'s current coordinates, the same as
        # the Ruby scoring would.
        def pack_with(rest)
          [@points + rest.flatten.pack("d*"), (@offsets + Native.path_offsets(rest, @offsets.last).drop(1)).pack("l*")]
        end
      end

      # `prefix.paths + rest` -- an ordinary, frozen sibling list for the
      # Ruby scoring -- that also remembers which leading part is packed.
      class SiblingPaths < Array
        attr_reader :prefix, :rest

        def initialize(prefix, rest)
          super(prefix.paths + rest)
          @prefix = prefix
          @rest = rest.dup
          freeze
        end
      end

      def refine_params
        [EdgeRouter::PathMetrics::EDGE_EPSILON, EdgeRouter::CROSSING_PENALTY, EdgeRouter::OVERLAP_TIE_TOLERANCE,
         EdgeRouter::LINE_OVERLAP_PENALTY, EdgeRouter::LINE_CROSSING_PENALTY]
      end
    end
  end
end
