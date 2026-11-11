# frozen_string_literal: true

module Archsight
  module Diagram
    class Graph
      private

      def build_node(block, parent, raw_edges)
        raise GraphError, "duplicate id #{block.id.inspect} (line #{block.line})" if @nodes_by_id.key?(block.id)
        raise GraphError, "#{block.kind} has an empty id (line #{block.line})" if block.id.strip.empty?

        Attributes.check_node!(block, ranks_modes: RANKS_MODES)
        if Attributes.leaf?(block) && block.attrs.key?("anchor") && block.attrs["extend"] != "false"
          raise GraphError, "anchor on #{block.kind} #{block.id.inspect} (line #{block.line}) only places a leaf that keeps its own size: add no-extend"
        end
        raise GraphError, "extend \"width\" on #{block.kind} #{block.id.inspect} (line #{block.line}) only applies to a direct child of a layer" if block.attrs["extend"] == "width" && !parent&.layer?

        node = Node.for(id: block.id, kind: block.kind, attrs: block.attrs, children: [], parent: parent,
                        anonymous: block.anonymous, line: block.line)
        @nodes_by_id[block.id] = node

        block.children.each do |child|
          case child
          when AST::Block
            node.children << build_node(child, node, raw_edges)
          when AST::Edge
            raw_edges << child
          when AST::Port
            add_port(node, child)
          end
        end

        node
      end

      def add_port(node, ast_port)
        Attributes.check_port!(ast_port, node)
        if (first = node.port(ast_port.id))
          raise GraphError, "duplicate port #{ast_port.id.inspect} on #{node.id.inspect} (line #{ast_port.line}, first defined at line #{first.line})"
        end

        node.ports << Port.new(id: ast_port.id, node: node, attrs: ast_port.attrs, line: ast_port.line)
      end

      # A top-level `badge "id" { ... }` / `line "dashed" { ... }`: each id once per kind.
      def add_definition(ast_definition)
        Attributes.check_definition!(ast_definition)
        key = [ast_definition.kind, ast_definition.id]
        if (first = @definitions[key])
          return if first.attrs == ast_definition.attrs # the same definition, e.g. from two included diagrams

          raise GraphError, "#{ast_definition.kind} #{ast_definition.id.inspect} already defined at line #{first.line} (line #{ast_definition.line})"
        end

        @definitions[key] = Definition.new(kind: ast_definition.kind, id: ast_definition.id, attrs: ast_definition.attrs, line: ast_definition.line)
      end

      # `badge "id"` on nodes and ports names a definition, `align "id"` another node.
      def check_references!
        @nodes_by_id.each_value do |node|
          check_badge!(node.badge, "#{node.kind} #{node.id.inspect}", node.line) if node.badge
          node.ports.each { |port| check_badge!(port.badge, "port #{port.ref.inspect}", port.line) if port.badge }
          check_align!(node) if node.align
        end
      end

      def check_badge!(id, where, line)
        return if @definitions.key?([:badge, id])

        known = @definitions.values.select { |d| d.kind == :badge }.map(&:id)
        hint = known.empty? ? " (define it at the top level: badge #{id.inspect} { tint \"orange\"; label \"...\" })" : Attributes.suggestion(id, known)
        raise GraphError, "unknown badge #{id.inspect} on #{where} (line #{line})#{hint}"
      end

      def check_align!(node)
        where = "#{node.kind} #{node.id.inspect} (line #{node.line})"
        entries = node.alignments
        raise GraphError, "align #{node.align.inspect} on #{where} has an empty entry" if entries.any? { |_, _, id| id.empty? }

        entries.group_by(&:first).each_value do |same_axis|
          next if same_axis.length == 1

          raise GraphError, "align #{node.align.inspect} on #{where} lines up #{same_axis.map { |_, e, _| e }.join(" and ")} on one axis; " \
                            "use one of left/center/right and one of top/middle/bottom"
        end
        entries.each { |_, _, id| check_align_target!(node, id, where) }
      end

      def check_align_target!(node, id, where)
        target = @nodes_by_id[id]
        unless target
          word, rest = id.split(/\s+/, 2)
          if rest
            raise GraphError, "unknown edge #{word.inspect} in align #{node.align.inspect} on #{where}; expected one of " \
                              "#{Node::ALIGN_EDGES.keys.join(", ")}#{Attributes.suggestion(word, Node::ALIGN_EDGES.keys)}"
          end
          raise GraphError, "align #{node.align.inspect} on #{where} names no node #{id.inspect}#{Attributes.suggestion(id, @nodes_by_id.keys)}"
        end
        return unless target.ancestors.include?(node) || node.ancestors.include?(target)

        raise GraphError, "align #{node.align.inspect} on #{where} names #{target == node ? "the node itself" : "a node it is nested with"}"
      end

      # A top-level `theme "..."`/`legend "..."` statement: each may appear
      # once, with one of its own allowed values.
      def apply_setting(setting)
        @setting_lines ||= {}
        key = setting.key
        if (first = @setting_lines[key])
          raise GraphError, "#{key} already set at line #{first} (line #{setting.line})"
        end

        check_setting_value(key, setting.value, SETTING_VALUES.fetch(key).call, setting.line)
        @setting_lines[key] = setting.line
        instance_variable_set(SETTING_IVARS.fetch(key), setting.value)
      end

      def check_setting_value(key, value, allowed, line)
        return if allowed.include?(value)

        raise GraphError, "unknown #{key} #{value.inspect} (line #{line}); expected one of #{allowed.join(", ")}"
      end

      def resolve_edge(ast_edge)
        from, from_port = endpoint(ast_edge.from)
        to, to_port = endpoint(ast_edge.to)
        raise GraphError, "connects #{from.id.inspect} to itself, which has no line to draw" if from == to

        Edge.new(from: from, to: to, attrs: ast_edge.attrs, direction: ast_edge.direction, line: ast_edge.line,
                 from_port: from_port, to_port: to_port)
      rescue GraphError => e
        raise GraphError, "#{e.message} (edge at line #{ast_edge.line})"
      end

      # An edge end: a node id, or `node.port` when no node has that whole id (namespaced ids contain dots too).
      def endpoint(ref)
        return [@nodes_by_id[ref], nil] if @nodes_by_id.key?(ref)

        owner = port_owner(ref)
        return [node(ref), nil] unless owner

        port_id = ref.delete_prefix("#{owner.id}.")
        port = owner.port(port_id)
        return [owner, port] if port

        known = owner.ports.map(&:id)
        listed = known.empty? ? "it has no ports" : "its ports: #{known.join(", ")}"
        raise GraphError, "unknown port #{port_id.inspect} on #{owner.id.inspect} (#{listed})#{Attributes.suggestion(port_id, known)}"
      end

      # The node `node.port` names, `nil` if the part before the last dot is no node
      def port_owner(ref)
        owner_id, dot, = ref.rpartition(".")
        dot.empty? ? nil : @nodes_by_id[owner_id]
      end

      def resolve_dataflow(ast_dataflow)
        group_index = ast_dataflow.hops.index { |h| h.is_a?(AST::DataFlowGroup) }

        if group_index.nil?
          hops = ast_dataflow.hops.map { |id| node(id) }
          return DataFlow.new(id: ast_dataflow.id, hops: hops, attrs: ast_dataflow.attrs, group: nil, line: ast_dataflow.line)
        end

        prefix = ast_dataflow.hops[0...group_index].map { |id| node(id) }
        suffix = ast_dataflow.hops[(group_index + 1)..].map { |id| node(id) }
        branches = ast_dataflow.hops[group_index].branches.map do |b|
          DataFlowBranch.new(hops: b.hops.map { |id| node(id) }, attrs: ast_dataflow.attrs.merge(b.attrs))
        end

        group = DataFlowGroup.new(prefix: prefix, branches: branches, suffix: suffix)
        DataFlow.new(id: ast_dataflow.id, hops: [], attrs: ast_dataflow.attrs, group: group, line: ast_dataflow.line)
      rescue GraphError => e
        raise GraphError, "#{e.message} (dataflow #{ast_dataflow.id.inspect} at line #{ast_dataflow.line})"
      end
    end
  end
end
