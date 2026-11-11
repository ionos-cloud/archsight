# frozen_string_literal: true

module Archsight
  module Diagram
    class Graph
      # `from_port`/`to_port` are the `Graph::Port` an end attaches to (`a -> b.port`), `nil` for the node itself.
      Edge = Struct.new(:from, :to, :attrs, :direction, :line, :from_port, :to_port, keyword_init: true) do
        def label
          attrs["label"]
        end

        def style
          attrs.fetch("style", "straight")
        end

        def relation
          attrs.fetch("relation", "dependency")
        end

        # `solid` (the relation's own stroke), `dashed` or `dotted`.
        def line_style
          attrs.fetch("line", "solid")
        end

        # The explicit `tint` attr, if any -- `nil` when unset, meaning
        # "use this relation's own fixed color" rather than falling back to
        # some default tint the way `Node#effective_tint` does (an edge
        # doesn't nest, so there's no darkening-depth concept to apply).
        def tint
          attrs["tint"]
        end

        # The looked-up `Relation` object (style + behavior flags) --
        # mirrors `Node#shape` (raw string) / `Node#representer` (looked-up
        # object): `#relation` itself stays the plain name, which is what
        # the source, `--relation` and every relation filter speak.
        def relation_type
          Relations.for(relation)
        end
      end
    end
  end
end
