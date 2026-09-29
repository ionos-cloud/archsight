# frozen_string_literal: true

module Archsight
  module Diagram
    class Graph
      private

      def build_node(block, parent, raw_edges)
        raise GraphError, "duplicate id #{block.id.inspect} (line #{block.line})" if @nodes_by_id.key?(block.id)
        raise GraphError, "#{block.kind} has an empty id (line #{block.line})" if block.id.strip.empty?

        Attributes.check_node!(block, ranks_modes: RANKS_MODES)

        node = Node.for(id: block.id, kind: block.kind, attrs: block.attrs, children: [], parent: parent,
                        anonymous: block.anonymous, line: block.line)
        @nodes_by_id[block.id] = node

        block.children.each do |child|
          case child
          when AST::Block
            node.children << build_node(child, node, raw_edges)
          when AST::Edge
            raw_edges << child
          end
        end

        node
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
        from = node(ast_edge.from)
        to = node(ast_edge.to)
        Edge.new(from: from, to: to, attrs: ast_edge.attrs, direction: ast_edge.direction, line: ast_edge.line)
      rescue GraphError => e
        raise GraphError, "#{e.message} (edge at line #{ast_edge.line})"
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
