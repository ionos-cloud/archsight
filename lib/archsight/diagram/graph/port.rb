# frozen_string_literal: true

module Archsight
  module Diagram
    class Graph
      # A labelled tab on a leaf's border (`port "id" { ... }`) that edges attach to with
      # `leaf.id`. `side`/`at` are the explicit placement, `nil` when left to `PortPlacement`.
      Port = Struct.new(:id, :node, :attrs, :line, keyword_init: true) do
        def label = attrs["label"] || id
        def side = attrs["side"]
        def at = attrs["at"]
        def badge = attrs["badge"]

        # `node.port`, as an edge names it
        def ref = "#{node.id}.#{id}"
      end

      # A top-level `badge "id" { tint; label }` or `line "style" { label }` (see `AST::Definition`).
      Definition = Struct.new(:kind, :id, :attrs, :line, keyword_init: true) do
        def label = attrs["label"] || id
        def tint = attrs.fetch("tint", "gray")
      end
    end
  end
end
