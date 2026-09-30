# frozen_string_literal: true

module Archsight
  module Diagram
    module Legend
      # Decides *what* belongs in the legend: exactly the shapes/
      # relations/dataflows/boundary actually used in the diagram (or
      # nothing at all, for a plain diagram using only default
      # components and dependency edges). `Renderer::LegendRenderer` only
      # decides *how* those rows look once assembled. `relations` are the
      # relations actually drawn (see `Legend.rows`).
      class Inventory
        def initialize(graph, relations:)
          @graph = graph
          @relations = relations
        end

        def rows
          return @rows if defined?(@rows)

          @rows = trivial? ? [] : shape_rows + relation_rows + dataflow_rows + swatch_rows
        end

        private

        # Nothing worth explaining: plain components and default relations
        # only.
        def trivial?
          (used_shapes - ["rectangle"]).empty? && @relations.all? { |r| Relations.for(r).default? } &&
            !boundary_present? && !application_present? && @graph.dataflows.empty? && used_tints.empty? &&
            tinted_containers.empty?
        end

        def shape_rows
          Representers.names.select { |s| used_shapes.include?(s) }.flat_map do |s|
            next [ShapeRow.new(Representers.for(s).legend_label, shape: s, tint: shape_tint(s))] unless s == "rectangle"

            # component and application share the "rectangle" shape but
            # are visually and semantically distinct, so they each get
            # their own legend row instead of collapsing into one.
            rows = []
            rows << ShapeRow.new("Component", shape: s, tint: shape_tint(s)) if component_present?
            rows << ShapeRow.new("Application", shape: s, tint: shape_tint(s, application: true), width_class: "asd-stroke-application") if application_present?
            rows
          end
        end

        def relation_rows
          Relations.names.select { |r| @relations.include?(r) }.map { |r| RelationRow.new(Relations.for(r).legend_label, relation: r) }
        end

        def dataflow_rows = @graph.dataflows.map { |df| DataflowRow.new(df.label || df.id, dataflow: df) }

        # The "Trust boundary" row, one dashed row per explicitly tinted
        # boundary/group/layer/stack -- named after its own label and kind,
        # since a flat "Blue"/"Purple" swatch (see `used_tints` below)
        # wouldn't say *which* box it is, or that it's dashed like a
        # boundary/group rather than a plain leaf's solid fill -- then one
        # flat swatch per tint used on a leaf.
        def swatch_rows
          rows = []
          rows << SwatchRow.new("Trust boundary", tint: Tints.for("red"), dash_class: "asd-swatch-boundary") if default_boundary_present?
          tinted_containers.each do |n|
            dash_class = n.boundary? ? "asd-swatch-boundary" : "asd-swatch-container"
            rows << SwatchRow.new(MarkdownText.like(n.label, "#{n.kind.to_s.capitalize} #{n.label}"), tint: Tints.for(n.effective_tint), dash_class: dash_class)
          end
          rows + used_tints.map { |t| SwatchRow.new(t.name.capitalize, tint: t) }
        end

        def used_shapes
          @used_shapes ||= leaf_nodes.map(&:shape).uniq
        end

        # A representative leaf node's own *kind* default (ignoring any
        # explicit override on that particular instance, and ignoring
        # which node it happens to be -- this row stands for the shape/
        # kind in general, not one specific node) -- `shape "file"`
        # overrides the kind's own default regardless of kind, matching
        # `Graph::Node#effective_tint`.
        def shape_tint(shape, application: false)
          return Tints.for("yellow") if shape == "file"

          node = leaf_nodes.find { |n| n.shape == shape && n.application? == application }
          Tints.for(node.default_tint)
        end

        # Only tints someone actually opted into via an explicit `tint`
        # attr -- every kind's own *default* tint (see
        # `Graph::Node#default_tint`) is deliberately left out, so a
        # diagram that never uses the attr keeps rendering no legend at
        # all (see the `trivial` diagram case above). Ordered by the registry's own canonical order
        # (`Tints.names`), not source order, so the legend is stable
        # regardless of which node happens to use a tint first. Container
        # nodes (group/boundary/layer/stack) are excluded -- their tint
        # gets its own dashed, per-node, per-label row instead (see
        # `tinted_containers` below), not a flat swatch, unless that same
        # tint is *also* used by a leaf elsewhere.
        def used_tints
          names = @graph.nodes_by_id.values.reject(&:container?).filter_map(&:tint).uniq
          Tints.names.select { |n| names.include?(n) }.map { |n| Tints.for(n) }
        end

        def boundary_present?
          @graph.nodes_by_id.values.any?(&:boundary?)
        end

        def default_boundary_present?
          @graph.nodes_by_id.values.any? { |n| n.boundary? && n.tint.nil? }
        end

        # Every explicitly tinted, *named* container (an anonymous
        # `layer`/`stack` never renders a box at all -- see
        # `NodeRenderer#render`'s `anonymous?` branch -- so tinting one is
        # inert and shouldn't get a legend row either), deduped by its own
        # displayed label + tint so a redundant/HA pair sharing both (e.g.
        # two same-tinted nodes both labeled "VM") collapses to one row.
        def tinted_containers
          @graph.nodes_by_id.values
                .select { |n| n.container? && !n.anonymous? && n.tint }
                .uniq { |n| ["#{n.kind.to_s.capitalize} #{n.label}", n.effective_tint] }
        end

        def component_present?
          leaf_nodes.any? { |n| n.shape == "rectangle" && !n.application? }
        end

        def application_present?
          leaf_nodes.any?(&:application?)
        end

        def leaf_nodes
          return @leaf_nodes if defined?(@leaf_nodes)

          @leaf_nodes = []
          collect_leaves(@graph.roots)
          @leaf_nodes
        end

        def collect_leaves(nodes)
          nodes.each do |n|
            n.leaf? ? @leaf_nodes << n : collect_leaves(n.children)
          end
        end
      end
    end
  end
end
