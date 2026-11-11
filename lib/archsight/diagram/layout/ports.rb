# frozen_string_literal: true

require_relative "../support/text_metrics"

module Archsight
  module Diagram
    class Layout
      # The size of a port's tab (see `Graph::Port`): its label in monospace at the edge-label font size, a
      # little padding around it, and room for its badge dot.
      class PortMetrics
        PADDING_X = 6.0
        PADDING_Y = 4.5
        BADGE_ROOM = 10.0
        # Never closer to a corner of the leaf than this, never closer to the next tab than `GAP`.
        MARGIN = 10.0
        GAP = 8.0

        def initialize(theme)
          @theme = theme
        end

        def font_size = @theme.edge_label_font_size
        def height = font_size + (2 * PADDING_Y)

        def width(port)
          chars = TextMetrics.lines(port.label).map { |line| TextMetrics.markdown_runs(line).sum { |content, _| content.length } }.max
          (chars * TextMetrics::MONO_WIDTH * font_size / 1000.0) + (2 * PADDING_X) + (port.badge ? BADGE_ROOM : 0.0)
        end

        # The length a side needs to hold `ports` side by side (`along` is the tab's size along that side).
        def side_length(ports, &)
          return 0.0 if ports.empty?

          ports.sum(&) + (GAP * (ports.length - 1)) + (2 * MARGIN)
        end

        # `[min width, min height]` of a leaf with `ports`. A port without a `side` may end up on either
        # side of the leaf, so it counts for the top and bottom alike (where most ports go).
        def leaf_minimum(ports)
          on = ->(side) { ports.select { |p| p.side == side || (p.side.nil? && %w[top bottom].include?(side)) } }
          tab_height = height
          [%w[top bottom].map { |side| side_length(on.call(side)) { |p| width(p) } }.max,
           %w[left right].map { |side| side_length(on.call(side)) { tab_height } }.max]
        end
      end

      # Puts every port's tab on its leaf's border, once the leaves have their final position: on its `side`
      # (or the side facing what its edges connect it to), at its `at` (or lined up with what its edges
      # connect it to, when that does not span the whole side; else spread in declaration order), the tabs of
      # one side never overlapping. A tab straddles the border, half inside the leaf. Two rounds, so ports
      # whose edges connect them to other ports settle on each other's place.
      class PortPlacement
        HORIZONTAL_SIDES = %i[top bottom].freeze

        def initialize(graph, boxes, theme:)
          @graph = graph
          @boxes = boxes
          @metrics = PortMetrics.new(theme)
        end

        # `{ "node.port" => Box }`
        def place
          ports = @graph.ports
          return {} if ports.empty?

          tabs = {}
          2.times { tabs = place_all(ports, tabs) }
          tabs.each_value(&:freeze_bounds!)
          tabs
        end

        private

        def place_all(ports, previous)
          sides = Hash.new { |h, k| h[k] = [] }
          ports.each_with_index do |port, index|
            box = @boxes[port.node.id]
            peers = peer_boxes(port, previous)
            side = (port.side || facing_side(box, peers)).to_sym
            width = @metrics.width(port)
            along = HORIZONTAL_SIDES.include?(side) ? width : @metrics.height
            wanted = port.at ? at_position(box, side, port.at, along) : preference(box, side, peers)
            sides[[port.node.id, side]] << { port: port, along: along, width: width, wanted: wanted, index: index }
          end

          sides.each_with_object({}) do |((node_id, side), members), tabs|
            box = @boxes[node_id]
            spread(box, side, members).each { |m| tabs[m[:port].ref] = tab_box(box, side, m[:position], m[:width]) }
          end
        end

        # The boxes at the other ends of `port`'s edges: the peer's tab once it is placed, else its leaf.
        def peer_boxes(port, previous)
          @graph.edges.filter_map do |edge|
            if edge.from_port.equal?(port)
              (edge.to_port && previous[edge.to_port.ref]) || @boxes[edge.to.id]
            elsif edge.to_port.equal?(port)
              (edge.from_port && previous[edge.from_port.ref]) || @boxes[edge.from.id]
            end
          end
        end

        # The side whose outside the peers' mean center lies furthest beyond (top without peers).
        def facing_side(box, peers)
          return "top" if peers.empty?

          dx = (peers.sum(&:x) / peers.length) - box.x
          dy = (peers.sum(&:y) / peers.length) - box.y
          if dy.abs - (box.height / 2.0) >= dx.abs - (box.width / 2.0)
            dy.negative? ? "top" : "bottom"
          else
            dx.negative? ? "left" : "right"
          end
        end

        # Where along its side a port lines up with its peers: the mean of their centers, leaving out a peer
        # that spans the whole side (it lines up anywhere). `nil` when no peer has a preference.
        def preference(box, side, peers)
          lo, hi = side_range(box, side)
          centers = peers.filter_map do |peer|
            peer_lo, peer_hi, center = span(peer, side)
            center unless peer_lo <= lo && peer_hi >= hi
          end
          centers.empty? ? nil : centers.sum / centers.length
        end

        def at_position(box, side, at, along)
          lo, hi = side_range(box, side)
          case at
          when "left", "top" then lo + (along / 2.0)
          when "right", "bottom" then hi - (along / 2.0)
          when "center" then (lo + hi) / 2.0
          else lo + (along / 2.0) + ((hi - lo - along) * at.to_f / 100.0)
          end
        end

        # Ports without a preference share the side evenly in declaration order, then every port is pushed
        # just far enough for the tabs not to overlap and to stay inside the side.
        def spread(box, side, members)
          lo, hi = side_range(box, side)
          free = members.select { |m| m[:wanted].nil? }
          free.each_with_index { |m, i| m[:wanted] = lo + ((hi - lo) * (i + 0.5) / free.length) }

          ordered = members.sort_by { |m| [m[:wanted], m[:index]] }
          ordered.each { |m| m[:position] = m[:wanted].clamp(lo + half(m), [lo + half(m), hi - half(m)].max) }
          ordered.each_cons(2) { |a, b| b[:position] = [b[:position], a[:position] + apart(a, b)].max }
          last = ordered.last
          last[:position] = [last[:position], hi - half(last)].min
          ordered.reverse.each_cons(2) { |b, a| a[:position] = [a[:position], b[:position] - apart(a, b)].min }
          ordered
        end

        def half(member) = member[:along] / 2.0

        # How far apart the centers of two neighbouring tabs must be.
        def apart(one, other) = half(one) + half(other) + PortMetrics::GAP

        # The part of a side a tab may sit on: inside the leaf's corners.
        def side_range(box, side)
          if HORIZONTAL_SIDES.include?(side)
            [box.left + PortMetrics::MARGIN, box.right - PortMetrics::MARGIN]
          else
            [box.top + PortMetrics::MARGIN, box.bottom - PortMetrics::MARGIN]
          end
        end

        def span(peer, side)
          HORIZONTAL_SIDES.include?(side) ? [peer.left, peer.right, peer.x] : [peer.top, peer.bottom, peer.y]
        end

        def tab_box(box, side, position, width)
          case side
          when :top then Box.new(position, box.top, width, @metrics.height)
          when :bottom then Box.new(position, box.bottom, width, @metrics.height)
          when :left then Box.new(box.left, position, width, @metrics.height)
          else Box.new(box.right, position, width, @metrics.height)
          end
        end
      end
    end
  end
end
