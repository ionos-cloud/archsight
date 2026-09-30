# frozen_string_literal: true

module Archsight
  module Diagram
    module AST
      # A container (`group`/`layer`/`stack`/`boundary`) or leaf
      # (`component`/`application`/`api`/`database`/`queue`/`actor`) "id" { ... }
      # block. Only containers may hold nested Block/Edge children.
      # `anonymous` is true for a `layer`/`stack` declared without an id —
      # `id` is then an internally generated placeholder nothing else can
      # reference.
      #
      # A plain Struct, not a kind-polymorphic hierarchy like `Graph::Node`'s
      # (see `Node.for`) -- nothing here ever branches on an `AST::Block`'s
      # class (`Parser` already knows leaf-ness from its own
      # `LEAF_KEYWORDS`), so there's no behavior a subclass per kind would
      # add over reading `kind` directly.
      Block = Struct.new(:kind, :id, :attrs, :children, :line, :anonymous, keyword_init: true) do
        def anonymous? = !!anonymous
      end

      # `from -> to { attrs }` (or `<->`/`--`) declaration. May appear at any
      # nesting depth. `direction` is :directed, :bidirectional, or
      # :undirected.
      Edge = Struct.new(:from, :to, :attrs, :direction, :line, keyword_init: true)

      # `dataflow "id" { hop "..."; hop "..."; ...; color "#hex"; label "..." }`
      # — an ordered multi-hop path, always top-level. `hops` is an array of
      # bare id strings (>= 2) and/or (at most one) `DataFlowGroup`, in path
      # order; `attrs` holds the remaining scalar attributes (`color`,
      # `label`).
      DataFlow = Struct.new(:id, :hops, :attrs, :line, keyword_init: true)

      # `hop group { hop "..."; branch { hop "..."; ...; label "..." } ... }`
      # — a single slot in a dataflow's hop list that fans out (or in) to
      # `branches` (>= 2) instead of one fixed next hop. A bare `hop "x"`
      # inside the group is sugar for `branch { hop "x" }`.
      DataFlowGroup = Struct.new(:branches, :line, keyword_init: true)

      # One alternative inside a `hop group` — `hops` (>= 1 id strings) is
      # its own private sub-chain; `attrs` holds any `label`/`color`
      # overrides for just this branch (merged over the parent dataflow's
      # own attrs at graph-resolution time).
      DataFlowBranch = Struct.new(:hops, :attrs, :line, keyword_init: true)

      # A top-level diagram-wide `key "value"` setting -- currently only
      # `theme "compact"` (see `Theme`).
      Setting = Struct.new(:key, :value, :line, keyword_init: true)
    end
  end
end
