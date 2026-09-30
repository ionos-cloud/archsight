# frozen_string_literal: true

module Archsight
  module Diagram
    class Parser
      # `columns "N"` on a container: sugar for wrapping its child blocks
      # in an anonymous `layer` of N anonymous `stack`s (one per column),
      # filled column-major -- the first column top-to-bottom, then the
      # next -- so a table of peers doesn't need that nesting spelled out
      # by hand. Rewritten here, at parse time, into exactly the AST the
      # hand-written nesting would produce, so nothing downstream (graph,
      # layout, `extend` inheritance, rendering) needs to know about it.
      # The including class must define `next_anonymous_id`.
      module TableLayout
        # Returns `children` with its blocks regrouped into columns; edges
        # stay direct children, since they only reference ids.
        def expand_columns(attrs, children, label, line)
          raw = attrs["columns"]
          return children if raw.nil?

          raise ParseError, "#{label} at line #{line}: columns must be a positive integer, got #{raw.inspect}" unless raw.match?(/\A[1-9]\d*\z/)

          blocks, edges = children.partition { |c| c.is_a?(AST::Block) }
          count = [raw.to_i, blocks.length].min
          return children if blocks.empty?

          base, remainder = blocks.length.divmod(count)
          columns = Array.new(count) do |i|
            cells = blocks.shift(base + (i < remainder ? 1 : 0))
            anonymous_block(:stack, cells, line)
          end

          [anonymous_block(:layer, columns, line), *edges]
        end

        private

        def anonymous_block(kind, children, line)
          AST::Block.new(kind: kind, id: next_anonymous_id, anonymous: true, attrs: {}, children: children, line: line)
        end
      end
    end
  end
end
