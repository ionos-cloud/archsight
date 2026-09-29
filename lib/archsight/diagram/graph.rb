# frozen_string_literal: true

require_relative "parser/ast"
require_relative "errors"
require_relative "style/representers"
require_relative "support/axis"
require_relative "style/relations"
require_relative "style/theme"
require_relative "legend/modes"
require_relative "graph/node"
require_relative "graph/edge"
require_relative "graph/dataflow"
require_relative "graph/attributes"
require_relative "graph/builder"

module Archsight
  module Diagram
    # Resolved graph model built from the parsed AST: a containment tree of
    # nodes/groups plus a flat, id-resolved list of edges. This is the shared
    # model that both Layout and Renderer consume.
    class Graph
      # `ranks "<mode>"`, on a container or at the top level: `auto` (rank a
      # group/boundary/top level whose children form a deep enough DAG),
      # `on` (rank in the container's own natural direction), `down`,
      # `right`, or `off`.
      RANKS_MODES = %w[auto on down right off].freeze

      # Each top-level setting's allowed values (evaluated lazily, when a
      # setting is actually checked), and where `Graph` keeps it.
      SETTING_VALUES = { "theme" => -> { Theme.names }, "legend" => -> { Legend::MODES }, "ranks" => -> { RANKS_MODES } }.freeze
      SETTING_IVARS = { "theme" => :@theme_name, "legend" => :@legend_mode, "ranks" => :@ranks_mode }.freeze

      attr_reader :roots, :nodes_by_id, :edges, :dataflows, :theme_name, :legend_mode, :ranks_mode

      def self.build(statements)
        new(statements)
      end

      def initialize(statements)
        @nodes_by_id = {}
        @roots = []
        raw_edges = []
        raw_dataflows = []

        statements.each do |stmt|
          case stmt
          when AST::Block
            @roots << build_node(stmt, nil, raw_edges)
          when AST::Edge
            raw_edges << stmt
          when AST::DataFlow
            raw_dataflows << stmt
          when AST::Setting
            apply_setting(stmt)
          end
        end

        raw_edges.each { |e| Attributes.check_edge!(e) }
        raw_dataflows.each_with_object({}) do |df, seen|
          if (first = seen[df.id])
            raise GraphError, "duplicate dataflow id #{df.id.inspect} (line #{df.line}, first defined at line #{first})"
          end

          seen[df.id] = df.line
          Attributes.check_dataflow!(df)
        end
        @edges = raw_edges.map { |e| resolve_edge(e) }
        @dataflows = raw_dataflows.map { |df| resolve_dataflow(df) }
      end

      def node(id)
        @nodes_by_id.fetch(id) do
          raise GraphError, "unknown id #{id.inspect}"
        end
      end
    end
  end
end
