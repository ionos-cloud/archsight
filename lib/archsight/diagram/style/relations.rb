# frozen_string_literal: true

module Archsight
  module Diagram
    # One small object per edge `relation`, mirroring `Representers`
    # (looked up by name, not baked into `Graph::Edge`'s own class): knows
    # its own rendering style (stroke/dash/arrowhead/legend label) plus the
    # per-relation behavior flags -- `curved?` (`Renderer::EdgeRenderer`'s
    # curve choice), `inverted_flow?` (which end sits above the other, for
    # `Layout::ForceSimulation`'s flow bias and `Layout::RankedArranger`'s
    # ranks), `tree_grouped?` (`Renderer#implements_tree_groups`'s
    # selection), and `default?` (`Legend::Inventory#trivial?`'s "nothing
    # unusual to show" check).
    class Relation
      attr_reader :name, :stroke, :dash, :arrow, :legend_label

      def initialize(name:, stroke:, dash:, arrow:, legend_label:, curved: false, inverted_flow: false,
                     tree_grouped: false, default: false)
        @name = name
        @stroke = stroke
        @dash = dash
        @arrow = arrow
        @legend_label = legend_label
        @curved = curved
        @inverted_flow = inverted_flow
        @tree_grouped = tree_grouped
        @default = default
      end

      def curved? = @curved
      def inverted_flow? = @inverted_flow
      def tree_grouped? = @tree_grouped
      def default? = @default
    end

    module Relations
      REGISTRY = {} # rubocop:disable Style/MutableConstant -- filled by .register

      def self.register(name, relation) = REGISTRY[name] = relation
      def self.for(name) = REGISTRY.fetch(name) { REGISTRY.fetch("dependency") }
      def self.names = REGISTRY.keys

      # The relations drawn unless asked otherwise (`--relation`): the
      # structural ones, not control/data flow.
      DEFAULT_FILTER = %w[dependency implements].freeze

      register("dependency", Relation.new(name: "dependency", stroke: "#4a5568", dash: nil, arrow: :filled,
                                          legend_label: "Dependency", default: true))
      # The interface is the stable point its implementers hang *below*,
      # even though the rendered arrow correctly points the other way
      # (adapter -> interface, UML convention) -- `inverted_flow?` only
      # affects `ForceSimulation#apply_flow`'s layout bias, never the
      # rendered arrow direction.
      register("implements", Relation.new(name: "implements", stroke: "#4a5568", dash: "6 3", arrow: :hollow,
                                          legend_label: "Implements", inverted_flow: true, tree_grouped: true))
      register("control", Relation.new(name: "control", stroke: "#b7791f", dash: "5 3", arrow: :filled,
                                       legend_label: "Control flow"))
      register("data", Relation.new(name: "data", stroke: "#2f855a", dash: "2 3", arrow: :filled,
                                    legend_label: "Data flow", curved: true))
    end
  end
end
