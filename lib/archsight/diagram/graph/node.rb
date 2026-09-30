# frozen_string_literal: true

require_relative "gap_spec"

module Archsight
  module Diagram
    class Graph
      # `Node.for` picks a real subclass per kind, so behaviour is
      # polymorphic (`leaf?`, `layer?`, `stack?`, `boundary?`,
      # `default_shape`, ...) rather than a comparison of symbols; `kind`
      # itself is the DSL keyword the node was declared with, kept for
      # what's shown about it (legend labels, `data-asd-kind`).
      Node = Struct.new(:id, :kind, :attrs, :children, :parent, :anonymous, :line, keyword_init: true) do
        def leaf? = false
        def container? = !leaf?
        def application? = false
        def boundary? = false
        def default_shape = nil

        # A real node is never the top level -- only `Layout::TopLevel`
        # (arranging `@graph.roots` themselves) is.
        def top_level? = false

        # The single axis this node's own children are packed/ranked along
        # (a `layer` packs along width, a `stack` along height) -- `nil` for
        # anything else (`group`/`boundary` are force-simulated in both
        # dimensions at once, with no single packing direction).
        def main_axis = nil
        def ranked? = !main_axis.nil?
        def layer? = main_axis == Axis::WIDTH
        def stack? = main_axis == Axis::HEIGHT

        def anonymous?
          !!anonymous
        end

        # `self`, then its parent, grandparent, ... up to (and including)
        # the root it descends from.
        def ancestors
          chain = []
          node = self
          while node
            chain << node
            node = node.parent
          end
          chain
        end

        def ancestor_ids = ancestors.map(&:id)

        def label
          attrs["label"] || id
        end

        def shape
          attrs.fetch("shape") { default_shape || "rectangle" }
        end

        # The explicit `tint` attr, if any -- `nil` when unset. Unlike
        # `extend`, a tint is never inherited from an ancestor; see
        # `effective_tint` for what actually gets rendered.
        def tint
          attrs["tint"]
        end

        # Every kind has its own default tint (see subclasses below), so a
        # node without an explicit `tint` attr is still drawn from the same
        # named palette (`Tints`) instead of a one-off hardcoded color --
        # `shape "file"` overrides the kind default, since a file icon reads
        # the same regardless of which leaf keyword declared it.
        def default_tint = "gray"

        def effective_tint
          tint || (shape == "file" ? "yellow" : default_tint)
        end

        # The nearest ancestor that actually renders a box -- skips past any
        # anonymous `layer`/`stack` (never drawn, see `NodeRenderer#render`'s
        # `anonymous?` branch), so it's transparent to `tint_depth` below
        # instead of silently breaking a same-tint chain just because it
        # happens to sit, invisibly, in between.
        def nearest_named_ancestor
          node = parent
          node = node.parent while node&.anonymous?
          node
        end

        # How many consecutive (box-rendering) ancestors share this node's
        # own `effective_tint` -- used to darken nested same-tinted boxes so
        # they stay distinguishable (see `Tint#fill`/`#border`). Stops at
        # the first ancestor with a *different* effective tint, so a
        # differently-tinted subtree never darkens just because it happens
        # to sit deep inside another tint's nesting.
        def tint_depth
          level = 0
          node = nearest_named_ancestor
          while node && node.effective_tint == effective_tint
            level += 1
            node = node.nearest_named_ancestor
          end
          level
        end

        def representer
          Representers.for(shape)
        end

        # Overrides this node's own sibling gap (see `GapSpec` for the
        # attr's own syntax). Unset (the overwhelming common case) just
        # returns `default` untouched.
        def gap(default)
          GapSpec.parse(attrs["gap"]).apply(default)
        end

        # `nil` (no `extend` attr on this node) inherits whatever the
        # nearest ancestor decided; any actual value overrides it --
        # literally `"false"` turns extension off for this node and
        # everything below it (until something deeper overrides it back
        # on), anything else (including `"true"`) turns it on. `"height"`
        # is the exception: it's a separate, vertical-only opt-in (see
        # `extend_height?`), so it leaves the inherited width decision
        # untouched.
        def extend?(inherited)
          raw = attrs["extend"]
          return inherited if raw.nil? || raw == "height"

          raw != "false"
        end

        # `extend "height"` on a direct child of a `layer` grows that
        # child's box to its tallest sibling's height, leaving its own
        # content top-aligned where it already sits. Never inherited --
        # only the node carrying the attr is affected.
        def extend_height?
          attrs["extend"] == "height"
        end

        def link
          attrs["link"]
        end

        # Why this node's `resource` reference couldn't be resolved (see
        # `ResourceLinks`), or `nil` when it has none or it resolved.
        def broken_link
          attrs["broken"]
        end

        # The padding and title band `Layout` reserves inside a container's
        # box -- none for an anonymous `layer`/`stack`, which never draws a
        # box of its own; `Legend::Frame` has its own fixed ones.
        def layout_padding(theme) = anonymous? ? 0.0 : theme.padding
        def layout_title_height(theme) = anonymous? ? 0.0 : theme.title_height

        # See `Legend::Entry`, sized by `Layout` from its row instead of from
        # a label/shape of its own.
        def legend_entry? = false

        # How this container arranges its children (`ranks "..."`, see
        # `Layout::RankArranger`): one of `Graph::RANKS_MODES`.
        def ranks_mode = attrs.fetch("ranks", "auto")

        def self.for(kind:, **rest)
          Node::KIND_CLASSES.fetch(kind, Node).new(kind: kind, **rest)
        end
      end

      class Component < Node
        def leaf? = true
        def default_shape = "rectangle"
        def default_tint = "blue"
      end

      class Application < Node
        def leaf? = true
        def application? = true
        def default_shape = "rectangle"
        def default_tint = "teal"
      end

      class Api < Node
        def leaf? = true
        def default_shape = "circle"
        def default_tint = "cyan"
      end

      class Database < Node
        def leaf? = true
        def default_shape = "cylinder"
        def default_tint = "purple"
      end

      class Queue < Node
        def leaf? = true
        def default_shape = "pipe"
        def default_tint = "pink"
      end

      class Actor < Node
        def leaf? = true
        def default_shape = "actor"
      end

      # Named `FileNode` (not `File`) to avoid shadowing `::File`, same
      # reason `Representers::FileRepresenter` isn't just `File`. Its own
      # default tint is left at the base `"gray"` -- `effective_tint`
      # already special-cases `shape == "file"` to `"yellow"` regardless of
      # kind, so a plain `component { shape "file" }` and this first-class
      # keyword render identically by default.
      class FileNode < Node
        def leaf? = true
        def default_shape = "file"
      end

      class Group < Node; end

      class Boundary < Node
        def boundary? = true
        def default_tint = "red"
      end

      class Layer < Node
        def main_axis = Axis::WIDTH
      end

      class Stack < Node
        def main_axis = Axis::HEIGHT
      end

      Node::KIND_CLASSES = {
        component: Component, application: Application, api: Api, database: Database,
        queue: Queue, actor: Actor, file: FileNode, group: Group, boundary: Boundary, layer: Layer, stack: Stack
      }.freeze
    end
  end
end
