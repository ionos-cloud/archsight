# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # The `id`/`data-asd-*` attributes that tie every rendered SVG element
      # back to the source object it was drawn for -- computed once, up
      # front, in *declaration* order (never render/routing order), so an
      # object keeps its id across renders as long as its own source
      # doesn't change.
      #
      # Every id is `asd-<kind>-<token>` (a node, dataflow, implements tree)
      # or `asd-edge-<from token>__<to token>`, plus `__<part>` for each
      # primitive drawn for it (`asd-node-db__body`, `asd-node-db__label`).
      # A token is its source id slugged down to `[A-Za-z0-9_-]` (see
      # `.slug`), which never contains `__` -- so `__` is always a
      # separator, never part of a source id, and no part id can ever equal
      # another object's own id. Tokens are unique per kind: a source id
      # that slugs onto an already-taken token gets `-2`, `-3`, ... -- with
      # every id that's already clean claiming its own token first, so a
      # clean id never gets bumped by a messier one declared before it.
      # A second edge between the same two nodes gets `__2`, `__3`, ...
      # (numeric, so never mistaken for a part name).
      #
      # The exact source id always travels alongside in `data-asd-src`
      # (`data-asd-from`/`data-asd-to` for an edge), and its source line in
      # `data-asd-line`, on the object's own wrapping `<g>` -- and on its
      # label, which lives in the separate text layer (see `TextRenderer`),
      # outside that `<g>`, so it also names its owner in `data-asd-owner`.
      #
      # Objects are keyed by identity: `Node`/`Edge`/`DataFlow` are Structs
      # with circular references, so hashing them by value would recurse
      # forever (see `Renderer#implements_tree_groups`).
      class ElementIds
        def self.slug(source)
          token = source.to_s.gsub(/[^A-Za-z0-9_-]/, "_").squeeze("_").delete_prefix("_").delete_suffix("_")
          token.empty? ? "x" : token
        end

        # One token per entry of `sources`, unique across all of them (see
        # the class docs for the collision order).
        def self.unique_tokens(sources)
          taken = Set.new
          tokens = sources.map { |s| s if slug(s) == s && taken.add?(s) }
          sources.each_with_index.map do |s, i|
            next tokens[i] if tokens[i]

            base = slug(s)
            token = base
            n = 1
            token = "#{base}-#{n += 1}" until taken.add?(token)
            token
          end
        end

        def initialize(graph)
          @ids = {}.compare_by_identity
          @node_tokens = {}.compare_by_identity

          nodes = graph.roots.flat_map { |root| subtree(root) }
          nodes.zip(self.class.unique_tokens(nodes.map(&:id))) do |node, token|
            @node_tokens[node] = token
            @ids[node] = "asd-node-#{token}"
          end

          per_pair = Hash.new(0)
          graph.edges.each do |edge|
            base = "asd-edge-#{@node_tokens.fetch(edge.from)}__#{@node_tokens.fetch(edge.to)}"
            n = (per_pair[base] += 1)
            @ids[edge] = n == 1 ? base : "#{base}__#{n}"
          end

          graph.dataflows.zip(self.class.unique_tokens(graph.dataflows.map(&:id))) do |df, token|
            @ids[df] = "asd-dataflow-#{token}"
          end
        end

        # The object's own id -- also the prefix of every `part` id. A
        # grouped dataflow's synthetic trunk/branch piece (see
        # `DataflowRouting#expanded_dataflows`) is its authored dataflow's
        # id plus the piece's own name: `asd-dataflow-flow__branch0`.
        def id(obj)
          return "#{id(obj.origin)}__#{obj.id.delete_prefix("#{obj.origin.id}$")}" if obj.respond_to?(:origin) && obj.origin

          @ids.fetch(obj)
        end

        def part(obj, name) = "#{id(obj)}__#{name}"

        # An implements tree has no source object of its own -- it's
        # every tree-grouped edge into one target -- so it's named after
        # that target.
        def tree(target) = "asd-tree-#{@node_tokens.fetch(target)}"

        # The attributes for the `<g>` wrapping everything drawn for `obj`.
        def group_attrs(obj)
          source = obj.respond_to?(:origin) && obj.origin ? obj.origin : obj
          { id: id(obj), "data-asd-kind": kind(source), **source_attrs(source), "data-asd-line": source.line }
        end

        # The attributes for `obj`'s label `<text>`: its own id, plus which
        # object it belongs to, since it isn't drawn inside that object's
        # `<g>`.
        def label_attrs(obj)
          source = obj.respond_to?(:origin) && obj.origin ? obj.origin : obj
          { id: part(obj, "label"), "data-asd-owner": id(obj), "data-asd-line": source.line }
        end

        private

        def subtree(node) = [node, *node.children.flat_map { |c| subtree(c) }]

        def kind(obj)
          case obj
          when Graph::Node then obj.kind.to_s
          when Graph::Edge then "edge"
          else "dataflow"
          end
        end

        def source_attrs(obj)
          return { "data-asd-from": obj.from.id, "data-asd-to": obj.to.id } if obj.is_a?(Graph::Edge)

          { "data-asd-src": obj.id }
        end
      end
    end
  end
end
