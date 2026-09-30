# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # Two `<style>` blocks: `style_block` holds every fill/stroke/font/dash
      # *presentation* class any renderer's `class="..."` attribute
      # references (see the individual renderers -- `NodeRenderer`,
      # `TextRenderer`, `PathRenderer`, `Representers`, `Legend::Row` -- for
      # what each class means), and is the one `Renderer#render`'s `style:`
      # option (embed/omit/link-elsewhere) actually controls; the cursor/
      # hover/`:has()` rules that make a dataflow's own legend-hover
      # highlight work live in `interaction_style_block` instead, which
      # stays embedded regardless of `style:` -- that behavior is wired to
      # this specific document's own generated markup (`data-dataflow`
      # attrs, `asd-dataflow` classes), not a swappable "look" a caller
      # replacing the presentation stylesheet would otherwise expect to
      # have to reimplement just to keep the diagram's own interactivity
      # working.
      #
      # Almost all of `style_block` is static -- the tint/relation/shape/
      # text vocabularies are small and fixed, knowable without looking at
      # `graph` at all (`Tint#fill_class`/`#border_class` are the single
      # source of truth for the 12 tints x `Tint::MAX_SHADE_LEVEL + 1`
      # levels this generates a rule for). The one exception is a colored
      # stroke override (`MarkerDefs.color_class`) -- a dataflow's own
      # arbitrary `color` attr, or a plain edge's `tint` resolved to a
      # hex -- which needs a rule generated per actual value used in *this*
      # diagram, mirroring how `MarkerDefs` itself already handles that
      # same case for arrowhead defs.
      class Stylesheet
        include SvgFormat

        # How much every other edge fades while an edge or node is hovered
        # (see `edge_hover_css`).
        HOVER_DIM_OPACITY = 0.2
        # An edge's invisible hover target (`PathRenderer#draw_hit_path`).
        HIT_STROKE_WIDTH = 10.0

        # `tree_ids` maps each implements-tree-grouped edge (by identity) to
        # its tree's id, so highlighting a stub also lights up the spine and
        # trunk it shares with its siblings.
        #
        # `marker_ids` are every arrowhead `<marker>` the document defines
        # (see `MarkerDefs#marker_ids`): a highlighted line swaps its own
        # for that marker's `-hover` twin, so its arrowhead doesn't double
        # in size right along with the line (see `hover_marker_css`).
        def initialize(graph, drawn_edges, ids: nil, tree_ids: {}.compare_by_identity, marker_ids: [], theme: Theme::DEFAULT)
          @graph = graph
          @marker_ids = marker_ids
          @drawn_edges = drawn_edges
          @ids = ids || ElementIds.new(graph)
          @tree_ids = tree_ids
          @theme = theme
        end

        def style_block
          css = [text_css, line_css, relation_css, shape_css, tint_css, legend_css, line_color_css].join("\n")
          wrap(css)
        end

        def interaction_style_block = wrap(hover_css)

        private

        def wrap(css)
          m = Markup.new
          m.element("style") { m.raw(css) }
          m.to_s
        end

        # Cursor/hover affordances, plus the animation that plays when a
        # dataflow's legend row is hovered.
        def hover_css
          <<~CSS.chomp
            .asd-link { cursor: pointer; }
            .asd-link:hover { opacity: 0.75; }
            .asd-legend-dataflow { cursor: pointer; }
            /* Every "asd-dataflow" group is a direct sibling of every
               other one (and of every node/edge) under the root svg
               element, itself a stacking context -- z-index alone is
               enough to reorder them, no isolation/position needed.
               Hovered, a dataflow jumps above every other dataflow/edge/
               node so it's never partially hidden underneath one it
               happens to cross. */
            .asd-dataflow:hover {
              z-index: 1000;
            }
            .asd-dataflow:hover .asd-dataflow-line {
              stroke-width: #{DATAFLOW_STROKE_WIDTH * 1.5};
              animation: asd-dataflow-flow 0.6s linear infinite;
            }
            #{dataflow_legend_hover_rules}
            @keyframes asd-dataflow-flow {
              to { stroke-dashoffset: -20; }
            }
            #{edge_hover_css}
          CSS
        end

        # Hovering an edge (its line, via the wide invisible `.asd-hit` path
        # over it, or its label) highlights it and its label; hovering a
        # node highlights its outgoing edges -- a leaf anywhere on its
        # shape, a container only on its own frame or title, since its
        # `<g>` also holds its children's (hovering a child highlights just
        # the child's edges). Meanwhile every other edge, edge label,
        # implements-tree line and dataflow fades: one static rule dims them
        # all whenever any hover source is hovered, and each source's own
        # id-based rule -- more specific -- brings its edges back.
        def edge_hover_css
          edges = @drawn_edges.to_a
          return "" if edges.empty?

          faded = ".asd-edge, .asd-edge-label, .asd-tree-line, .asd-dataflow, .asd-dataflow-label"
          # A hovered edge's own `<g>` needs no rule of its own -- only what
          # it has to reach outside that `<g>` does (see `edge_rules`).
          # `svg:has(...)` in front just outranks the dim rule.
          static = <<~CSS
            .asd-hit { fill: none; stroke: transparent; stroke-width: #{HIT_STROKE_WIDTH}; pointer-events: stroke; }
            :is(#{faded}) { transition: opacity 0.15s ease; }
            svg:has(.asd-edge:hover, .asd-edge-label:hover, .asd-hover-source:hover) :is(#{faded}) { opacity: #{HOVER_DIM_OPACITY}; }
            svg:has(.asd-edge:hover) .asd-edge:hover { opacity: 1; }
            .asd-edge:hover .asd-line { #{highlight_line} }
            #{hover_marker_css}
          CSS

          edge_rules = edges.map { |e| edge_rules(e) }
          node_rules = edges.group_by { |e| e.from.id }.map do |_id, outgoing|
            node = outgoing.first.from
            target = node.leaf? ? @ids.id(node) : @ids.part(node, "frame")
            highlight_rules([target, @ids.part(node, "label")], outgoing)
          end
          static + (edge_rules + node_rules).join
        end

        # A highlighted line: `EDGE_HOVER_STROKE_WIDTH` thick, with its
        # arrowheads swapped for their `-hover` twins (see
        # `hover_marker_css`).
        def highlight_line
          "stroke-width: #{EDGE_HOVER_STROKE_WIDTH}; marker-start: var(--asd-hover-marker-start); " \
            "marker-end: var(--asd-hover-marker-end);"
        end

        # Every line names its own arrowhead(s) in its `marker-start`/
        # `marker-end` attributes; one rule per marker turns that into the
        # `--asd-hover-marker-*` custom property `highlight_line` swaps in,
        # so no highlight rule needs to know which arrowhead any line uses.
        # A line with no marker on one end leaves that property unset, and
        # `marker-*: var(...)` then falls back to `none`.
        def hover_marker_css
          @marker_ids.map do |id|
            %w[start end].map do |side|
              %(.asd-line[marker-#{side}="url(##{id})"] { --asd-hover-marker-#{side}: url(##{MarkerDefs.hover_id(id)}); })
            end
          end.flatten.join("\n")
        end

        # What highlighting edge `e` involves beyond its own `<g>` (see the
        # generic `.asd-edge:hover` rules): its label, painted in the
        # separate text layer, and -- for an implements-tree stub -- the
        # spine and trunk it shares. Nothing at all for an unlabelled plain
        # edge.
        def edge_rules(edge)
          label = "##{@ids.part(edge, "label")}" if edge.label
          tree = @tree_ids[edge]
          return "" unless label || tree

          group = "##{@ids.id(edge)}"
          active = "svg:has(#{[group, label].compact.map { |t| "#{t}:hover" }.join(",")})"
          tree_lines = ["##{tree}__spine", "##{tree}__trunk"] if tree
          strokes = []
          strokes << "svg:has(#{label}:hover) #{group} .asd-line" if label
          strokes << "#{active} :is(#{tree_lines.join(",")})" if tree

          <<~CSS
            #{active} :is(#{[(group if label), label, *tree_lines].compact.join(",")}) { opacity: 1; font-weight: bold; }
            #{strokes.join(", ")} { #{highlight_line} }
          CSS
        end

        # The two rules highlighting `edges` whenever any element of
        # `triggers` (ids) is hovered: their `<g>`s, labels and tree lines
        # back to full opacity (and the labels bold -- `font-weight` does
        # nothing on a `<g>` or path), and their lines thicker. Kept as
        # terse as it reads well: a dense diagram gets one pair per edge
        # plus one per node with outgoing edges.
        def highlight_rules(triggers, edges)
          active = "svg:has(#{triggers.map { |t| "##{t}:hover" }.join(",")})"
          groups = edges.map { |e| "##{@ids.id(e)}" }
          labels = edges.map { |e| "##{@ids.part(e, "label")}" }
          trees = edges.filter_map { |e| @tree_ids[e] }.uniq.flat_map { |t| ["##{t}__spine", "##{t}__trunk"] }
          lines = ["#{active} :is(#{groups.join(",")}) .asd-line"]
          lines << "#{active} :is(#{trees.join(",")})" unless trees.empty?

          <<~CSS
            #{active} :is(#{(groups + labels + trees).join(",")}) { opacity: 1; font-weight: bold; }
            #{lines.join(", ")} { #{highlight_line} }
          CSS
        end

        # One generated rule per authored dataflow: hovering its legend row
        # (`.asd-legend-dataflow[data-dataflow="<id>"]`, see
        # `Renderer::LegendRenderer#render`) animates every rendered piece sharing
        # that same id (a grouped dataflow's shared trunk and every branch,
        # all tagged with the authored id -- see
        # `Renderer::DataflowRenderer#render`), wherever each sits in the
        # document -- `:has()` matches regardless of document order, unlike
        # a sibling combinator, which is why the legend (drawn after the
        # diagram) can still reach lines drawn before it.
        def dataflow_legend_hover_rules
          @graph.dataflows.map do |df|
            id = escape(df.id)
            selector = %(svg:has(.asd-legend-dataflow[data-dataflow="#{id}"]:hover) .asd-dataflow[data-dataflow="#{id}"])
            <<~CSS
              #{selector} { z-index: 1000; }
              #{selector} .asd-dataflow-line { stroke-width: #{DATAFLOW_STROKE_WIDTH * 1.5}; animation: asd-dataflow-flow 0.6s linear infinite; }
            CSS
          end.join
        end

        # One `.asd-fs-N` rule per font size the diagram's theme actually
        # renders text at (see `Theme#font_sizes`).
        def text_css
          font_size_rules = @theme.font_sizes.map { |size| ".asd-fs-#{size} { font-size: #{size}px; }\n" }.join
          <<~CSS.chomp
            .asd-text-halo { stroke: #fff; stroke-width: 3; stroke-linejoin: round; paint-order: stroke; }
            .asd-text { fill: #{TextRenderer::TEXT_COLOR}; }
            #{font_size_rules.chomp}
            .asd-text-anchor-middle { text-anchor: middle; }
            .asd-text-anchor-start { text-anchor: start; }
            .asd-text-baseline-central { dominant-baseline: central; }
            .asd-text-bold { font-weight: bold; }
            .asd-underline { text-decoration: underline; }
            .asd-run-bold { font-weight: bold; }
            .asd-run-italic { font-style: italic; }
            .asd-run-underline { text-decoration: underline; }
          CSS
        end

        def line_css
          <<~CSS.chomp
            .asd-line { fill: none; }
            .asd-stroke-thin { stroke-width: #{EDGE_STROKE_WIDTH}; }
            .asd-stroke-application { stroke-width: 2.5; }
            .asd-dataflow-line { stroke-width: #{DATAFLOW_STROKE_WIDTH}; transition: stroke-width 0.15s ease; }
            .asd-dataflow-halo { fill: none; stroke: #fff; stroke-width: #{DataflowRenderer::DATAFLOW_HALO_WIDTH}; stroke-linecap: round; }
          CSS
        end

        # One rule per registered relation (4), bundling its stroke color +
        # dasharray together -- relation-intrinsic, never mixed
        # independently the way a tint's fill/stroke are (see `tint_css`).
        def relation_css
          Relations.names.map do |name|
            r = Relations.for(name)
            dash = r.dash ? " stroke-dasharray: #{r.dash};" : ""
            ".asd-relation-#{name} { stroke: #{r.stroke};#{dash} }"
          end.join("\n")
        end

        # `rx` is deliberately *not* in here -- unlike `fill`/`stroke`/
        # `stroke-width`/`stroke-dasharray` (long-standing SVG1.1
        # presentation attributes with universal CSS support), `rx`/`ry` are
        # newer SVG2 geometry properties only recently CSS-settable and
        # unreliably supported outside a couple of evergreen browsers --
        # `Representers::Rectangle`/`NodeRenderer`/`Legend::SwatchRow` all
        # set it as a plain attribute instead.
        def shape_css
          <<~CSS.chomp
            .asd-canvas-bg { fill: #fff; }
            .asd-fill-none { fill: none; }
            .asd-shape-file { stroke-linejoin: round; }
            .asd-container { stroke-dasharray: 4 3; }
            .asd-container-boundary { stroke-dasharray: 8 4; }
            .asd-broken-link > :is(rect, path, ellipse, polygon, polyline, circle, line) { stroke-dasharray: 4 3; opacity: 0.6; }
          CSS
        end

        # `fill`/`stroke` kept as two separate one-property rules per
        # `(tint, level)` pair (not one combined rule) so they compose
        # freely wherever only one of the two is wanted -- e.g. a group's
        # own label text (`.asd-text` default fill) sits right next to
        # its box's `fill_class`/`border_class`, with no risk of colliding
        # over a property both would otherwise set.
        def tint_css
          Tints.names.flat_map do |name|
            tint = Tints.for(name)
            (0..Tint::MAX_SHADE_LEVEL).flat_map do |level|
              [".#{tint.fill_class(level)} { fill: #{tint.fill(level)}; }",
               ".#{tint.border_class(level)} { stroke: #{tint.border(level)}; }"]
            end
          end.join("\n")
        end

        def legend_css
          <<~CSS.chomp
            .asd-legend-bg { fill: #fafbfc; stroke-width: 1; }
            .asd-swatch { stroke-width: 2; }
            .asd-swatch-boundary { stroke-dasharray: 4 2; }
            .asd-swatch-container { stroke-dasharray: 3 2; }
          CSS
        end

        # A compound selector (not a bare `.asd-dataflow-color-...` rule)
        # so it reliably wins on specificity over `.asd-relation-<name>`'s
        # own `stroke` regardless of declaration order, rather than relying
        # on this method running after `relation_css` in `style_block`.
        # Covers both sources of a colored stroke override: a dataflow's
        # own `color` attr (always styled as the "data" relation) and a
        # plain edge's `tint` resolved to its border color (styled as
        # whatever relation that edge actually uses).
        def line_color_css
          dataflow_rules = @graph.dataflows.filter_map(&:color).uniq.map { |c| override_rule("data", c) }
          edge_rules = @drawn_edges.tinted_lines.map { |relation, tint| override_rule(relation, Tints.for(tint).border(0)) }
          (dataflow_rules + edge_rules).join("\n")
        end

        def override_rule(relation, color)
          ".asd-relation-#{relation}.#{MarkerDefs.color_class(color)} { stroke: #{color}; }"
        end
      end
    end
  end
end
