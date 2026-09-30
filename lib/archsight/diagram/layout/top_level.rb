# frozen_string_literal: true

module Archsight
  module Diagram
    class Layout
      # "No enclosing group": the container `@graph.roots` are arranged in,
      # answering the same questions a container `Graph::Node` does (its
      # gap, whether it's a layer/stack, ...) so `RankArranger`,
      # `ForceSimulation` and `RootAlignment` can treat the top level like
      # any other container. `top_level?` is what tells it apart where it
      # genuinely differs -- `RankTopology#representative_in` looks a
      # top-level node up differently, and its `ranks` mode comes from the
      # graph (`Graph#ranks_mode`) rather than an attribute.
      module TopLevel
        module_function

        def gap(default) = default
        def anonymous? = false
        def extend?(inherited) = inherited
        def top_level? = true
        def leaf? = false
        def main_axis = nil
        def ranked? = false
        def layer? = false
        def stack? = false
      end
    end
  end
end
