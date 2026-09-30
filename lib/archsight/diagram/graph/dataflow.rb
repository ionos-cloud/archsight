# frozen_string_literal: true

module Archsight
  module Diagram
    class Graph
      # A `dataflow "id" { hop "..."; hop "...", ...; color "#hex"; label
      # "..." }` — an ordered, always-rendered multi-hop path. `hops` holds
      # resolved `Node`s (>= 2), in path order -- empty when `group` is
      # present instead (a dataflow has either a flat `hops` chain or a
      # single `group`, never both). `line` is the source line of the
      # authored `dataflow`; `origin` is only set on the synthetic
      # trunk/branch pieces `DataflowRouting#expanded_dataflows` splits a
      # grouped dataflow into, pointing back at the authored one.
      DataFlow = Struct.new(:id, :hops, :attrs, :group, :line, :origin, keyword_init: true) do
        def label
          attrs["label"]
        end

        def color
          attrs["color"]
        end
      end

      # A `hop group` — `prefix`/`suffix` are the resolved `Node`s shared by
      # every branch (either may be empty, but not both — a group needs
      # somewhere to fan out from or into), `branches` (>= 2) are the
      # diverging alternatives.
      DataFlowGroup = Struct.new(:prefix, :branches, :suffix, keyword_init: true)

      # One branch of a `hop group` — `hops` (>= 1) are this branch's own
      # `Node`s; `attrs` is already fully merged (this branch's own
      # `label`/`color`, if any, over the parent dataflow's), so it's
      # self-contained the same way `DataFlow#attrs` is.
      DataFlowBranch = Struct.new(:hops, :attrs, keyword_init: true) do
        def label
          attrs["label"]
        end

        def color
          attrs["color"]
        end
      end
    end
  end
end
