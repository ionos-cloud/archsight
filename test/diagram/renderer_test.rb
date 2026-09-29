# frozen_string_literal: true

require_relative "../test_helper"
require "rexml/document"

class DiagramRendererTest < Minitest::Test
  def test_renders_a_well_formed_svg_document_with_nodes_groups_and_edges
    source = <<~SRC
      group "vpc" {
        label "VPC"
        component "a" { label "A" }
        component "b" { label "B" }
      }
      a -> b { style "orthogonal"; label "calls" }
    SRC
    svg = Archsight::Diagram.render(source)

    doc = REXML::Document.new(svg)

    assert_equal "svg", doc.root.name

    rects = drawn(doc, "rect")
    # 1 background rect + 1 group rect + 2 node rects
    assert_equal 4, rects.length

    texts = drawn(doc, "text").map(&:text)

    assert_includes texts, "VPC"
    assert_includes texts, "A"
    assert_includes texts, "B"
    assert_includes texts, "calls"

    assert_equal 1, drawn(doc, "path").length
    assert_equal(1, doc.root.get_elements("defs/marker").count { |m| !m.attributes["id"].end_with?("-hover") })
  end

  def test_escapes_special_characters_in_labels
    svg = Archsight::Diagram.render(%(component "a" { label "A & <B>" }\n))

    assert_includes svg, "A &amp; &lt;B&gt;"
    refute_includes svg, "A & <B>"
  end

  def test_renders_each_leaf_keyword_s_default_shape_as_its_own_svg_element
    source = <<~SRC
      component "rect" { }
      api "circ" { }
      database "cyl" { }
      queue "hex" { }
      actor "act" { }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))

    # Each non-trivial shape also gets a matching sample icon in the
    # auto-generated legend, so every count below is the node itself plus
    # its legend icon.
    assert_equal 2, drawn(doc, "ellipse").length
    assert_equal 2, drawn(doc, "circle").length # actor's head, main + legend
    # cylinder and pipe each draw 2 <path> elements (body + cap arc);
    # no edges in this source.
    assert_equal 8, drawn(doc, "path").length
  end

  def test_renders_a_file_shape_override_as_a_folded_corner_document_icon
    doc = REXML::Document.new(Archsight::Diagram.render(%(component "cfg" { label "Config"; shape "file" }\n)))

    paths = doc.root.get_elements("//path[not(ancestor::marker)]")
    # One filled body path (the folded page outline) plus one unfilled
    # crease path (the fold line) -- for the node itself and its legend
    # sample icon, so 4 total. Both the node's own fill and the legend's
    # sample icon use the "file" shape's own default tint (yellow),
    # regardless of which leaf kind declared it.
    assert_equal 4, paths.length
    classes = paths.map { |p| p.attributes["class"] }

    assert_equal(2, classes.count { |c| c.include?(Archsight::Diagram::Tints.for("yellow").fill_class) })
    assert_equal(2, classes.count { |c| c.include?("asd-fill-none") })
    assert_includes drawn(doc, "text").map(&:text), "File / document"
  end

  def test_renders_a_module_shape_override_as_a_sharp_cornered_rectangle_distinct_in_the_legend
    # For rows packed into a "gap 0" stack (e.g. a middleware pipeline) --
    # unlike the default rectangle, it has no rx (sharp corners, reading
    # as one continuous slab when several sit edge-to-edge) -- and its
    # own legend row/label distinguishes it from a plain component.
    doc = REXML::Document.new(Archsight::Diagram.render(%(component "m" { label "Logging"; shape "module" }\n)))

    rects = doc.root.get_elements("//rect").select { |r| r.attributes["class"]&.split&.include?(Archsight::Diagram::Tints.for("blue").border_class) }

    assert_equal 2, rects.length # the node itself + its legend sample icon
    rects.map { |r| r.attributes["rx"] }.each { |rx| assert_nil rx }
    assert_includes drawn(doc, "text").map(&:text), "Module"
  end

  def test_gives_rounded_corners_to_components_groups_boundaries_and_legend_swatches
    # Regression test: `rx` briefly moved into a CSS class alongside real
    # presentation properties during the stylesheet refactor -- unlike
    # `fill`/`stroke`/`stroke-width`/`stroke-dasharray` (long-standing
    # SVG1.1 presentation attributes with universal CSS support), `rx`/`ry`
    # are newer SVG2 geometry properties, unreliably supported as CSS
    # outside a couple of evergreen browsers, so they have to stay plain
    # attributes.
    source = <<~SRC
      group "g" {
        tint "blue"
        boundary "b" { component "a" { } }
      }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))
    rx_values = doc.root.get_elements("//rect").map { |r| r.attributes["rx"] }.compact

    # component, group, boundary, legend swatch
    assert_includes rx_values, "6"
    assert_includes rx_values, "8"
    assert_includes rx_values, "10"
    assert_includes rx_values, "3"
  end

  def test_nudges_a_datastore_s_label_down_from_dead_center_since_the_rounded_top_cap_takes_more_room
    doc = REXML::Document.new(Archsight::Diagram.render(%(database "db" { label "DB" }\n)))
    box_center_y = 20.0 + (60.0 / 2.0) # CANVAS_MARGIN + half the default leaf height
    text = drawn(doc, "text").find { |t| t.text == "DB" }

    assert_operator text.attributes["y"].to_f, :>, box_center_y
  end

  def test_hides_control_data_edges_by_default_but_shows_them_with_a_wider_relation_filter
    source = <<~SRC
      component "a" { }
      component "b" { }
      a -> b { relation "control" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    layout = Archsight::Diagram::Layout.compute(graph)

    default_svg = Archsight::Diagram::Renderer.render(graph, layout)

    assert_equal 0, drawn(REXML::Document.new(default_svg), "path").length

    all_svg = Archsight::Diagram::Renderer.render(graph, layout, relation_filter: Archsight::Diagram::Relations.names)
    doc = REXML::Document.new(all_svg)

    assert_equal 1, drawn(doc, "path").length
    assert_includes all_svg, "asd-relation-control"
    assert_includes all_svg, ".asd-relation-control { stroke: #b7791f"
  end

  def test_gives_implements_edges_a_hollow_arrowhead_and_dashed_line
    source = <<~SRC
      component "a" { }
      component "b" { }
      a -> b { relation "implements" }
    SRC
    svg = Archsight::Diagram.render(source)

    assert_includes svg, "arrow-implements"
    assert_includes svg, 'fill="none" stroke="#4a5568" stroke-width="1.5" />' # hollow triangle
  end

  def test_renders_bidirectional_edges_with_markers_on_both_ends_and_undirected_edges_with_none
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      a <-> b
      b -- c
    SRC
    svg = Archsight::Diagram.render(source)

    assert_match(/marker-start="url\(#arrow-dependency\)".*marker-end="url\(#arrow-dependency\)"|marker-end="url\(#arrow-dependency\)".*marker-start="url\(#arrow-dependency\)"/, svg)

    undirected_line = svg.lines.find { |l| l.include?("M ") && !l.include?("marker") }

    refute_nil undirected_line
  end

  def test_gives_boundary_containers_a_distinct_style_and_includes_a_trust_boundary_legend_entry
    source = <<~SRC
      boundary "b" {
        component "a" { }
      }
    SRC
    svg = Archsight::Diagram.render(source)

    assert_includes svg, Archsight::Diagram::Tints.for("red").border_class
    assert_includes svg, "Trust boundary"
  end

  def test_gives_the_boundary_title_a_bigger_untinted_font_instead_of_matching_the_boundary_s_own_tint
    source = <<~SRC
      boundary "b" { tint "purple"; label "Boundary Title"; component "a" { } }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))
    title = doc.root.get_elements("//text").find { |t| t.text == "Boundary Title" }

    assert_includes title.attributes["class"], "asd-fs-15"
    assert_includes title.attributes["class"], "asd-text" # the same plain default fill every other label uses
    refute_match(/asd-(fill|stroke)-purple/, title.attributes["class"])
  end

  def test_gives_a_tinted_boundary_a_gradient_fill_and_a_drop_shadow_filter_both_referencing_generated_defs
    source = <<~SRC
      boundary "b" { tint "teal"; component "a" { } }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))

    boundary_rect = doc.root.get_elements("//rect").find { |r| r.attributes["class"]&.split&.include?("asd-container-boundary") }
    gradient_id = Archsight::Diagram::Renderer::ContainerEffects.gradient_id("teal", 0)

    assert_equal "url(##{gradient_id})", boundary_rect.attributes["fill"]
    assert_equal "url(##{Archsight::Diagram::Renderer::ContainerEffects.shadow_filter_id})", boundary_rect.attributes["filter"]

    gradient = doc.root.get_elements("//linearGradient[@id='#{gradient_id}']").first

    refute_nil gradient
    stops = gradient.get_elements("stop")

    assert_equal 2, stops.length
    assert_equal Archsight::Diagram::Tints.for("teal").fill(0), stops[0].attributes["stop-color"]
    assert_equal Archsight::Diagram::Tints.for("teal").fill(1), stops[1].attributes["stop-color"]

    assert_equal 1, doc.root.get_elements("//filter[@id='#{Archsight::Diagram::Renderer::ContainerEffects.shadow_filter_id}']").length
  end

  def test_gives_a_named_group_layer_stack_the_same_gradient_fill_as_a_boundary_but_no_drop_shadow
    source = <<~SRC
      group "g" { tint "teal"; component "a" { } }
      layer "l" { tint "teal"; component "b" { } }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))
    gradient_id = Archsight::Diagram::Renderer::ContainerEffects.gradient_id("teal", 0)

    containers = doc.root.get_elements("//rect").select { |r| r.attributes["class"]&.split&.include?("asd-container") }

    assert_equal 2, containers.length # the group and the named layer
    containers.each do |rect|
      assert_equal "url(##{gradient_id})", rect.attributes["fill"]
      assert_nil rect.attributes["filter"] # the shadow stays boundary-only
    end
  end

  def test_emits_the_shadow_filter_exactly_once_for_multiple_boundaries_and_not_at_all_with_none
    source = <<~SRC
      boundary "b1" { component "a" { } }
      boundary "b2" { component "c" { } }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))

    assert_equal 1, doc.root.get_elements("//filter").length

    plain = Archsight::Diagram.render(%(component "a" { }\n))

    refute_includes plain, "<filter"
  end

  def test_tints_a_group_s_border_and_background_and_darkens_a_nested_box_sharing_the_same_tint
    source = <<~SRC
      group "outer" {
        tint "blue"
        group "inner" {
          tint "blue"
          component "x" { }
        }
      }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))
    rects = drawn(doc, "rect")
    # rects[0] is the full-canvas background; the group boxes are drawn
    # (depth-first) before any legend rows, so [1]/[2] are outer/inner.
    outer_rect = rects[1]
    inner_rect = rects[2]

    blue = Archsight::Diagram::Tints.for("blue")

    assert_equal "url(##{Archsight::Diagram::Renderer::ContainerEffects.gradient_id("blue", 0)})", outer_rect.attributes["fill"]
    assert_includes outer_rect.attributes["class"], blue.border_class(0)
    assert_equal "url(##{Archsight::Diagram::Renderer::ContainerEffects.gradient_id("blue", 1)})", inner_rect.attributes["fill"]
    assert_includes inner_rect.attributes["class"], blue.border_class(1)
    refute_equal outer_rect.attributes["fill"], inner_rect.attributes["fill"]
  end

  def test_doesn_t_darken_a_nested_box_whose_own_tint_differs_from_its_parent_s
    source = <<~SRC
      group "outer" {
        tint "blue"
        group "inner" {
          tint "green"
          component "x" { }
        }
      }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))
    rects = drawn(doc, "rect")
    outer_rect = rects[1]
    inner_rect = rects[2]

    assert_equal "url(##{Archsight::Diagram::Renderer::ContainerEffects.gradient_id("blue", 0)})", outer_rect.attributes["fill"]
    assert_equal "url(##{Archsight::Diagram::Renderer::ContainerEffects.gradient_id("green", 0)})", inner_rect.attributes["fill"]
  end

  def test_gives_each_tinted_group_layer_stack_its_own_dashed_legend_row_named_after_its_label_deduping_pairs
    source = <<~SRC
      group "vm1" { tint "blue"; label "VM"; component "a" { } }
      group "vm2" { tint "blue"; label "VM"; component "b" { } }
      group "other" { tint "green"; label "Other"; component "c" { } }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))
    texts = drawn(doc, "text").map(&:text)

    assert_includes texts, "Group VM"
    assert_includes texts, "Group Other"
    # vm1/vm2 share both label and tint -- one row, not two.
    assert_equal 1, texts.count("Group VM")

    vm_swatch = doc.root.get_elements("//rect").find do |r|
      classes = r.attributes["class"].to_s.split
      classes.include?(Archsight::Diagram::Tints.for("blue").fill_class) && classes.include?("asd-swatch-container")
    end

    assert_includes vm_swatch.attributes["class"], Archsight::Diagram::Tints.for("blue").border_class
  end

  def test_gives_a_tinted_boundary_its_own_dashed_named_legend_row_instead_of_a_flat_tint_swatch
    source = <<~SRC
      boundary "kubernetes" { tint "teal"; label "Kubernetes"; component "a" { } }
      boundary "plain" { component "b" { } }
      component "c" { tint "teal" }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))
    texts = drawn(doc, "text").map(&:text)

    assert_includes texts, "Boundary Kubernetes"
    assert_includes texts, "Trust boundary"
    assert_includes texts, "Teal"

    boundary_row_rect = doc.root.get_elements("//rect").find do |r|
      classes = r.attributes["class"].to_s.split
      classes.include?(Archsight::Diagram::Tints.for("teal").fill_class) && classes.include?("asd-swatch-boundary")
    end

    assert_includes boundary_row_rect.attributes["class"], Archsight::Diagram::Tints.for("teal").border_class

    # "c" (a plain leaf, no name of its own worth borrowing) still falls
    # back to a flat, solid "Teal" swatch -- distinct from the dashed
    # boundary row above.
    flat_teal_swatch = doc.root.get_elements("//rect").find do |r|
      classes = r.attributes["class"].to_s.split
      classes.include?("asd-swatch") && classes.include?(Archsight::Diagram::Tints.for("teal").fill_class) &&
        !classes.include?("asd-swatch-boundary") && !classes.include?("asd-swatch-container")
    end

    refute_nil flat_teal_swatch
  end

  # style:

  def test_style_embeds_the_generated_style_block_by_default
    svg = Archsight::Diagram.render(source)

    assert_includes svg, "<style>"
    refute_includes svg, "<?xml-stylesheet"
  end

  def test_style_omits_the_presentation_rules_with_style_none_keeping_class_attributes_and_interaction_rules
    svg = Archsight::Diagram.render(source, style: "none")

    refute_includes svg, ".asd-fs-13" # a presentation rule -- gone
    refute_includes svg, "<?xml-stylesheet"
    assert_includes svg, 'class="asd-canvas-bg"' # elements still carry their classes
    assert_includes svg, ".asd-link" # hover/interaction rules stay embedded regardless
  end

  def test_style_links_an_external_stylesheet_for_any_other_style_value_keeping_interaction_rules
    svg = Archsight::Diagram.render(source, style: "https://example.com/theme.css")

    refute_includes svg, ".asd-fs-13"
    assert_equal %(<?xml-stylesheet type="text/css" href="https://example.com/theme.css"?>\n), svg.lines[1]
    assert_includes svg, ".asd-link"
  end

  def test_style_keeps_the_dataflow_legend_hover_highlight_working_even_with_style_none
    source_with_dataflow = <<~SRC
      component "a" { }
      component "b" { }
      dataflow "flow" { hop "a"; hop "b" }
    SRC
    svg = Archsight::Diagram.render(source_with_dataflow, style: "none")

    assert_includes svg, 'svg:has(.asd-legend-dataflow[data-dataflow="flow"]:hover)'
  end

  def test_style_xml_escapes_the_linked_url
    svg = Archsight::Diagram.render(source, style: "https://example.com/a?x=1&y=2")

    assert_includes svg, 'href="https://example.com/a?x=1&amp;y=2"'
  end

  def test_omits_the_legend_for_a_plain_diagram_using_only_components_and_dependency_edges
    source = <<~SRC
      component "a" { }
      component "b" { }
      a -> b
    SRC
    refute_includes Archsight::Diagram.render(source), "Legend"
  end

  def test_includes_a_legend_listing_exactly_the_shapes_and_relations_actually_drawn
    source = <<~SRC
      api "a" { }
      component "b" { }
      a -> b { relation "implements" }
    SRC
    svg = Archsight::Diagram.render(source)

    assert_includes svg, "Legend"
    assert_includes svg, "API / endpoint"
    assert_includes svg, "Implements"
    refute_includes svg, "Datastore"
    refute_includes svg, "Control flow"
  end

  def test_gives_application_a_visually_distinct_rectangle_from_component_with_separate_legend_rows
    source = <<~SRC
      component "comp" { }
      application "app" { }
    SRC
    svg = Archsight::Diagram.render(source)

    assert_includes svg, "Component"
    assert_includes svg, "Application"

    doc = REXML::Document.new(svg)
    # 1 background rect + component + application + 2 legend sample rects
    classes = drawn(doc, "rect").map { |r| r.attributes["class"] }

    assert_operator classes.uniq.length, :>, 2
  end

  def test_omits_the_legend_for_a_diagram_with_no_edges_at_all
    # Regression test: the "trivial" check required relations to equal
    # exactly ["dependency"], but a diagram with zero edges has
    # used_relations == [], which isn't equal to that -- so a plain
    # diagram of disconnected boxes got a spurious empty-looking legend.
    svg = Archsight::Diagram.render(%(component "a" { }\ncomponent "b" { }\n))

    refute_includes svg, "Legend"
  end

  def test_prefers_a_direct_line_by_default_switching_to_orthogonal_only_when_it_would_cut_through_another_box
    # Regression test for the "least overdrawings" routing rule: an
    # unstyled edge should default to the simplest (straight) path, not
    # a fixed rule about length or diagonal-ness, and only switch to an
    # orthogonal route when going straight would draw through some other
    # box that isn't part of the edge itself.
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "d" { }
      component "blocker" { }
      a -> b
      c -> d
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(300, 200, 100, 60), # same diagonal geometry as c -> d
      "c" => Archsight::Diagram::Layout::Box.new(500, 0, 100, 60),
      "d" => Archsight::Diagram::Layout::Box.new(800, 200, 100, 60),
      "blocker" => Archsight::Diagram::Layout::Box.new(150, 100, 60, 40) # sits exactly on a -> b's straight line
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 900, height: 300)

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    segment_counts = drawn(doc, "path").map { |p| p.attributes["d"].split.length / 3 }

    assert_operator segment_counts[0], :>, 2 # a->b: routes around "blocker" instead of through it
    assert_equal 2, segment_counts[1] # c->d: identical shape, nothing in the way, stays direct
  end

  def test_splits_a_box_s_side_into_separate_attachment_points_when_more_than_one_edge_shares_it
    # Regression test: two edges leaving the same side of the same box
    # both default to that side's center, so they'd start out from the
    # exact same point and read as one merged line instead of two
    # distinct connections -- each should get its own point instead,
    # evenly spread across the side (symmetric here, since "x" and "y"
    # are mirror images of each other around "hub").
    source = <<~SRC
      component "hub" { }
      component "x" { }
      component "y" { }
      hub -> x
      hub -> y
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "hub" => Archsight::Diagram::Layout::Box.new(300, 0, 100, 60),
      "x" => Archsight::Diagram::Layout::Box.new(200, 200, 100, 60),
      "y" => Archsight::Diagram::Layout::Box.new(400, 200, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 600, height: 300)

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    exit_xs = drawn(doc, "path").map { |p| p.attributes["d"].split[1].to_f }

    assert_equal 2, exit_xs.uniq.length # previously both exited at hub.x (300.0)
    assert_in_delta 300.0, exit_xs.sum / 2.0, 0.01 # still centered on "hub" as a whole
  end

  def test_steers_a_converging_edge_off_a_sibling_edge_s_line_when_an_equally_clear_alternative_exists
    # Regression test: two sibling boxes both connecting to the same
    # wide target end up funneling through the same corner point
    # (`single_turn_horizontal_first`'s exit-side isn't available since
    # both boxes' x sit inside the target's span), so their final
    # segment into the target is identical -- routed independently,
    # neither edge has any reason to avoid the other's line. Refining
    # against sibling paths should steer one of them onto a route that
    # doesn't run along the other's.
    source = <<~SRC
      component "kubestore" { }
      component "kubecrypt" { }
      component "k8s_api" { }
      kubestore -> k8s_api { style "orthogonal" }
      kubecrypt -> k8s_api { style "orthogonal" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "kubestore" => Archsight::Diagram::Layout::Box.new(100, 0, 100, 60),
      "kubecrypt" => Archsight::Diagram::Layout::Box.new(300, 0, 100, 60),
      "k8s_api" => Archsight::Diagram::Layout::Box.new(210, 300, 300, 60)
    }
    Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 400)
    edge_routing = Archsight::Diagram::EdgeRouting.new(graph, boxes)

    edge_paths = edge_routing.compute_paths(graph.edges)
    a, b = edge_paths.map(&:points)

    assert_operator Archsight::Diagram::EdgeRouter::PathMetrics.overlap_length(a, [b]), :>, 0 # confirms the scenario actually needs fixing

    edge_routing.refine_line_overlap!(edge_paths)
    a, b = edge_paths.map(&:points)

    assert_equal(0.0, Archsight::Diagram::EdgeRouter::PathMetrics.overlap_length(a, [b]))
  end

  def test_keeps_three_edges_converging_on_the_same_target_from_crossing_each_other
    # Regression test for examples/iam_hexagonal.asd's kubestore/kubecrypt/
    # kuberbac -> k8s_api: with only one round of refinement, an edge
    # routed early (before its later siblings have settled into their own
    # final shape) has nothing to react to yet, and can end up crossing a
    # sibling's line that only exists from the *next* edge's refinement --
    # a single declaration-order pass can't see that coming. A second
    # round, seeing everyone's already-refined lines, should catch it.
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(File.read(File.expand_path("fixtures/iam_hexagonal.asd", __dir__))))
    layout = Archsight::Diagram::Layout.compute(graph)
    renderer = Archsight::Diagram::Renderer.new(graph, layout, relation_filter: Archsight::Diagram::Relations.names)
    edge_routing = Archsight::Diagram::EdgeRouting.new(graph, layout.boxes)

    edge_paths = edge_routing.compute_paths(renderer.send(:individually_routed_edges))
    edge_routing.refine_line_overlap!(edge_paths)

    into_k8s_api = edge_paths.select { |ep| ep.edge.to.id == "k8s_api" }

    into_k8s_api.combination(2).each do |a, b|
      assert_equal 0, Archsight::Diagram::EdgeRouter::PathMetrics.crossing_edges_count(a.points, [b.points]),
                   "#{a.edge.from.id} -> k8s_api crosses #{b.edge.from.id} -> k8s_api"
    end
  end

  def test_never_overrides_an_edge_s_explicit_style_even_when_it_draws_through_another_box
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "blocker" { }
      a -> b { style "straight" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(500, 400, 100, 60),
      "blocker" => Archsight::Diagram::Layout::Box.new(250, 200, 80, 80)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 600, height: 500)

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    path_d = drawn(doc, "path").first.attributes["d"]

    assert_equal 2, path_d.split.length / 3
  end

  def test_curves_a_plain_relation_data_edge_s_route_but_leaves_other_relations_straight
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      a -> b { style "orthogonal"; relation "data" }
      c -> b { style "orthogonal"; relation "dependency" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 120, 60),
      "b" => Archsight::Diagram::Layout::Box.new(300, 300, 120, 60),
      "c" => Archsight::Diagram::Layout::Box.new(600, 0, 120, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 700, height: 400)

    svg = Archsight::Diagram::Renderer.render(graph, layout, relation_filter: Archsight::Diagram::Relations.names)
    doc = REXML::Document.new(svg)
    paths = drawn(doc, "path")

    data_path = paths.find { |p| p.attributes["class"]&.split&.include?("asd-relation-data") }
    dependency_path = paths.find { |p| p.attributes["class"]&.split&.include?("asd-relation-dependency") }

    assert_includes data_path.attributes["d"], " C "
    refute_includes dependency_path.attributes["d"], " C "
    assert_includes dependency_path.attributes["d"], " L "
  end

  def test_draws_3_implements_edges_to_the_same_target_as_a_shared_tree_instead_of_independent_lines
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "target" { }
      a -> target { relation "implements" }
      b -> target { relation "implements" }
      c -> target { relation "implements" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 200, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 200, 100, 60),
      "c" => Archsight::Diagram::Layout::Box.new(400, 200, 100, 60),
      "target" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 300)

    svg = Archsight::Diagram::Renderer.render(graph, layout, relation_filter: Archsight::Diagram::Relations.names)
    doc = REXML::Document.new(svg)
    paths = drawn(doc, "path")

    assert_equal 5, paths.length # 1 spine + 3 branches + 1 trunk, not 3 full independent lines
    trunk_paths = paths.select { |p| p.attributes["marker-end"] == "url(#arrow-implements)" }

    assert_equal 1, trunk_paths.length # only the trunk carries an arrowhead
  end

  def test_draws_a_shared_tree_for_exactly_two_things_implementing_the_same_target_too
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "target" { }
      a -> target { relation "implements" }
      b -> target { relation "implements" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 200, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 200, 100, 60),
      "target" => Archsight::Diagram::Layout::Box.new(100, 0, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 300, height: 300)

    svg = Archsight::Diagram::Renderer.render(graph, layout, relation_filter: Archsight::Diagram::Relations.names)
    doc = REXML::Document.new(svg)
    paths = drawn(doc, "path")

    assert_equal 4, paths.length # 1 spine + 2 branches + 1 trunk, not 2 full independent lines
    trunk_paths = paths.select { |p| p.attributes["marker-end"] == "url(#arrow-implements)" }

    assert_equal 1, trunk_paths.length
  end

  def test_still_renders_an_individual_line_when_only_one_thing_implements_the_target
    source = <<~SRC
      component "a" { }
      component "target" { }
      a -> target { relation "implements" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 200, 100, 60),
      "target" => Archsight::Diagram::Layout::Box.new(100, 0, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 300, height: 300)

    svg = Archsight::Diagram::Renderer.render(graph, layout, relation_filter: Archsight::Diagram::Relations.names)
    doc = REXML::Document.new(svg)
    paths = drawn(doc, "path")

    assert_equal 1, paths.length # a lone implementer has no sibling to share a spine with
  end

  def test_excludes_a_hand_styled_edge_from_its_group_s_tree_without_forcing_its_siblings_out_too
    # "c" is styled by hand, so it's never folded into a tree -- but "a"
    # and "b" are still an eligible pair on their own and get their
    # usual shared tree, rather than the one customized edge knocking
    # the whole group back to fully individual rendering.
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "target" { }
      a -> target { relation "implements" }
      b -> target { relation "implements" }
      c -> target { relation "implements"; style "straight" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 200, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 200, 100, 60),
      "c" => Archsight::Diagram::Layout::Box.new(400, 200, 100, 60),
      "target" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 300)

    svg = Archsight::Diagram::Renderer.render(graph, layout, relation_filter: Archsight::Diagram::Relations.names)
    doc = REXML::Document.new(svg)
    trunk_paths = drawn(doc, "path").select { |p| p.attributes["marker-end"] == "url(#arrow-implements)" }

    assert_equal 2, trunk_paths.length # one shared trunk for a+b's tree, one individual line for c
  end

  def test_recolors_a_tinted_edge_s_line_and_arrowhead_to_match_leaving_its_dash_arrow_shape_alone
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      a -> b { tint "purple" }
      a -> c { relation "implements"; tint "purple" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(300, 0, 100, 60),
      "c" => Archsight::Diagram::Layout::Box.new(0, 300, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 400, height: 400)

    svg = Archsight::Diagram::Renderer.render(graph, layout, relation_filter: Archsight::Diagram::Relations.names)
    doc = REXML::Document.new(svg)
    purple = Archsight::Diagram::Tints.for("purple")
    slug = Archsight::Diagram::Renderer::MarkerDefs.color_class(purple.border(0))

    dependency_path = drawn(doc, "path").find { |p| p.attributes["class"]&.split&.include?("asd-relation-dependency") }
    implements_path = drawn(doc, "path").find { |p| p.attributes["class"]&.split&.include?("asd-relation-implements") }

    assert_includes dependency_path.attributes["class"], slug
    assert_includes implements_path.attributes["class"], slug

    # Same tint, but two different relations -- each still needs its own,
    # differently-shaped marker (a collision here would leave one edge's
    # arrowhead silently wrong-shaped).
    assert_equal "url(#arrow-color-dependency-#{Archsight::Diagram::Renderer::MarkerDefs.color_slug(purple.border(0))})", dependency_path.attributes["marker-end"]
    assert_equal "url(#arrow-color-implements-#{Archsight::Diagram::Renderer::MarkerDefs.color_slug(purple.border(0))})", implements_path.attributes["marker-end"]
    refute_equal implements_path.attributes["marker-end"], dependency_path.attributes["marker-end"]

    both_markers = doc.root.get_elements("//marker").select do |m|
      m.attributes["id"]&.include?(purple.border(0).delete_prefix("#")) && !m.attributes["id"].end_with?("-hover")
    end

    assert_equal 2, both_markers.length
  end

  def test_excludes_a_tinted_implements_edge_from_its_group_s_tree_same_as_a_hand_styled_one
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "target" { }
      a -> target { relation "implements" }
      b -> target { relation "implements" }
      c -> target { relation "implements"; tint "purple" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 200, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 200, 100, 60),
      "c" => Archsight::Diagram::Layout::Box.new(400, 200, 100, 60),
      "target" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 300)

    svg = Archsight::Diagram::Renderer.render(graph, layout, relation_filter: Archsight::Diagram::Relations.names)
    doc = REXML::Document.new(svg)
    paths = drawn(doc, "path")

    assert_equal 5, paths.length # 1 spine + 2 branches + 1 trunk for a+b's tree, 1 individual (tinted) line for c

    # c's own line still carries an arrowhead (just a tinted one, not the
    # plain shared "arrow-implements" marker a+b's trunk uses).
    arrowed = paths.select { |p| p.attributes["marker-end"] }

    assert_equal 2, arrowed.map { |p| p.attributes["marker-end"] }.uniq.length
  end

  def test_doesn_t_add_a_legend_row_for_a_tinted_edge_still_one_row_per_relation_in_its_base_color
    source = <<~SRC
      component "a" { }
      application "b" { }
      a -> b { tint "purple" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60)
    }
    layout = Archsight::Diagram::Layout.attach_legend(graph, Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 300, height: 100))

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    labels = drawn(doc, "text").map(&:text)

    refute_includes labels, "Purple"
    assert_equal 1, labels.count("Dependency") # just the one "Dependency" row, unaffected by the tint

    dependency_icon = doc.root.get_elements("//line").find { |l| l.attributes["class"]&.split&.include?("asd-relation-dependency") }

    refute_includes dependency_icon.attributes["class"], "asd-dataflow-color-" # base color, not tinted
  end

  def test_draws_no_box_or_label_for_an_anonymous_layer_stack_only_its_children
    source = <<~SRC
      stack {
        component "a" { label "A" }
        component "b" { label "B" }
      }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))

    # 1 background rect + 2 leaf rects -- none for the anonymous stack.
    assert_equal 3, drawn(doc, "rect").length
    texts = drawn(doc, "text").map(&:text)

    assert_equal %w[A B], texts.sort
  end

  # Archsight::Diagram::Renderer::PathGeometry
  # .simplify_points

  def test_path_geometry_simplify_points_drops_interior_points_within_tolerance_of_the_chord_between_neighbors
    # A near-straight run (tiny 1-unit jogs) plus one real, sharp turn.
    points = [[0.0, 0.0], [50.0, 1.0], [100.0, 0.0], [100.0, 100.0]]

    simplified = Archsight::Diagram::Geometry.simplify_points(points, 6.0)

    assert_equal [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]], simplified
  end

  def test_path_geometry_simplify_points_always_keeps_the_first_and_last_point_even_when_everything_is_collinear
    points = [[0.0, 0.0], [10.0, 0.0], [20.0, 0.0], [30.0, 0.0]]

    simplified = Archsight::Diagram::Geometry.simplify_points(points, 6.0)

    assert_equal [[0.0, 0.0], [30.0, 0.0]], simplified
  end

  # .limit_turn_angles

  def test_path_geometry_limit_turn_angles_relaxes_a_sharp_elbow_within_the_cap_without_moving_the_endpoints
    # A hard 90-degree elbow: straight right, then straight up.
    points = [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]]

    relaxed = Archsight::Diagram::Geometry.limit_turn_angles(points, 70.0)

    assert_equal [0.0, 0.0], relaxed.first
    assert_equal [100.0, 100.0], relaxed.last
    assert_operator turn_angle(relaxed[0], relaxed[1], relaxed[2]), :<=, 70.0 + 0.1
  end

  def test_path_geometry_limit_turn_angles_leaves_a_gentle_bend_that_s_already_within_the_cap_untouched
    points = [[0.0, 0.0], [100.0, 0.0], [190.0, 30.0]]
    original_turn = turn_angle(points[0], points[1], points[2])

    assert_operator original_turn, :<=, 70.0 # sanity check the scenario is actually gentle

    relaxed = Archsight::Diagram::Geometry.limit_turn_angles(points, 70.0)

    assert_equal points, relaxed
  end

  def test_path_geometry_limit_turn_angles_settles_a_chain_of_several_sharp_corners_so_all_respect_the_cap
    points = [[0.0, 0.0], [50.0, 0.0], [50.0, 50.0], [100.0, 50.0], [100.0, 100.0]]

    relaxed = Archsight::Diagram::Geometry.limit_turn_angles(points, 70.0)

    (1...(relaxed.length - 1)).each do |i|
      angle = turn_angle(relaxed[i - 1], relaxed[i], relaxed[i + 1])

      assert_operator angle, :<=, 70.1
    end
  end

  def test_always_renders_a_dataflow_unaffected_by_the_default_relation_filter
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      dataflow "flow" {
        hop "a"
        hop "b"
        hop "c"
        color "#2f855a"
        label "the flow"
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60),
      "c" => Archsight::Diagram::Layout::Box.new(400, 0, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 100)

    # Default relation_filter (dependency/implements only) -- a dataflow
    # is not a Graph::Edge/relation at all, so it isn't subject to it.
    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    paths = doc.root.get_elements("//path[not(ancestor::marker)]")

    # One white halo path plus one colored path -- a single, continuous
    # polyline through every hop, not one path per segment.
    assert_equal 2, paths.length
    colored = paths.select { |p| p.attributes["class"]&.split&.include?("asd-dataflow-line") }

    assert_equal 1, colored.length
    assert_includes colored.first.attributes["class"], "asd-dataflow-color-2f855a"

    # One arrowhead, at the final point.
    assert_equal "url(#arrow-color-data-2f855a)", colored.first.attributes["marker-end"]

    # "b" is an intermediate hop: the route entering it from "a" is
    # nudged into its interior (on b's left edge, x=150, offset in);
    # the outgoing route toward "c" is re-anchored to that same single
    # point rather than getting its own independently-nudged exit point
    # (see `compute_dataflow_routes`) -- so the box is touched at one
    # off-center point, not two close-but-different ones. A dataflow's
    # line is a smooth centripetal Catmull-Rom spline (cubic Bezier "C"
    # commands) through its waypoints rather than straight "L" segments.
    # Here a/b/c sit in a straight row with nothing to route around, so
    # the endpoint stubs `dataflow_ensure_stub` inserts leaving "a"/
    # entering "c" end up exactly collinear with the rest of the route
    # and get simplified back out (see the re-simplify step right after
    # they're inserted) -- a stub only survives when it's a real
    # deviation.
    d = colored.first.attributes["d"]

    assert d.start_with?("M 50.00 0.00 C"), "expected #{d.inspect} to start with \"M 50.00 0.00 C\""
    assert d.end_with?("350.00 0.00"), "expected #{d.inspect} to end with \"350.00 0.00\""
    assert_equal 2, d.scan(" C ").length # one Bezier segment per pair of the 3 surviving waypoints

    assert_includes drawn(doc, "text").map(&:text), "the flow"
  end

  def test_offsets_two_dataflows_sharing_an_intermediate_hop_to_opposite_sides_of_it
    source = <<~SRC
      component "a1" { }
      component "a2" { }
      component "shared" { }
      component "b1" { }
      component "b2" { }
      dataflow "flow1" { hop "a1"; hop "shared"; hop "b1" }
      dataflow "flow2" { hop "a2"; hop "shared"; hop "b2" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a1" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "a2" => Archsight::Diagram::Layout::Box.new(0, 200, 100, 60),
      "shared" => Archsight::Diagram::Layout::Box.new(200, 100, 100, 60),
      "b1" => Archsight::Diagram::Layout::Box.new(400, 0, 100, 60),
      "b2" => Archsight::Diagram::Layout::Box.new(400, 200, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 300)

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    colored = doc.root.get_elements("//path[not(ancestor::marker)]").select { |p| p.attributes["class"]&.split&.include?("asd-dataflow-line") }

    # The on-curve point ending the second "C" command is the nudged
    # entry waypoint at "shared" -- its y is what should differ between
    # the two dataflows (see the comment above).
    midpoints_y = colored.map { |p| p.attributes["d"].scan(/C [\d.-]+ [\d.-]+ [\d.-]+ [\d.-]+ [\d.-]+ ([\d.-]+)/)[1][0].to_f }

    assert_equal 2, midpoints_y.length
    refute_equal midpoints_y[1], midpoints_y[0] # opposite sides of "shared"'s center (y=100)
    assert_in_delta 100.0, midpoints_y.sum / 2.0, 0.01 # symmetric around its center
  end

  def test_falls_back_to_the_data_relation_s_stroke_dash_marker_when_a_dataflow_omits_color
    source = <<~SRC
      component "a" { }
      component "b" { }
      dataflow "flow" { hop "a"; hop "b" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 300, height: 100)

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    path = doc.root.get_elements("//path[not(ancestor::marker)]").find { |p| p.attributes["class"]&.split&.include?("asd-dataflow-line") }

    assert_includes path.attributes["class"], "asd-relation-data"
    refute_match(/asd-dataflow-color-/, path.attributes["class"])
    assert_equal "url(#arrow-data)", path.attributes["marker-end"] # reuses the plain relation marker, no per-color one
  end

  def test_adds_one_legend_row_per_dataflow_labeled_by_its_own_label_or_id_if_unlabeled
    source = <<~SRC
      component "a" { }
      component "b" { }
      dataflow "flow1" { hop "a"; hop "b"; label "first flow" }
      dataflow "flow2" { hop "a"; hop "b" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60)
    }
    layout = Archsight::Diagram::Layout.attach_legend(graph, Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 300, height: 100))

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)

    texts = doc.root.get_elements("//text").map(&:text)

    assert_includes texts, "first flow"
    assert_includes texts, "flow2"
  end

  def test_grows_the_canvas_to_the_left_and_top_for_a_legend_attached_there
    source = %(component "a" { }\ncomponent "b" { }\na -> b { relation "data" }\n)
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(100, 100, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(300, 100, 100, 60)
    }
    filter = Archsight::Diagram::Relations.names

    %w[left top].each do |side|
      result = Archsight::Diagram::Layout::Result.new(boxes: boxes.transform_values(&:dup), width: 400, height: 200)
      layout = Archsight::Diagram::Layout.attach_legend(graph, result, legend: side, relation_filter: filter)
      frame = layout.boxes[layout.legend.frame.id]
      min_x, min_y, width, height = Archsight::Diagram::Renderer.render(graph, layout, relation_filter: filter)[/viewBox="([^"]*)"/, 1].split.map(&:to_f)

      assert_operator min_x, :<=, frame.left, side
      assert_operator min_y, :<=, frame.top, side
      assert_operator min_x + width, :>=, frame.right, side
      assert_operator min_y + height, :>=, frame.bottom, side
    end
  end

  def test_tags_a_dataflow_s_line_s_and_its_legend_row_with_the_same_data_dataflow_id_for_css_only_hover
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "d" { }
      dataflow "provision_vm" {
        hop "a"
        hop "b"
        hop group {
          hop "c"
          hop "d"
        }
        color "#8E44AD"
        label "vm"
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60),
      "c" => Archsight::Diagram::Layout::Box.new(400, 0, 100, 60),
      "d" => Archsight::Diagram::Layout::Box.new(400, 200, 100, 60)
    }
    layout = Archsight::Diagram::Layout.attach_legend(graph, Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 300))

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)

    # The trunk plus both branches (3 pieces) all carry the *authored*
    # id, not their own synthetic "$prefix"/"$branch0"/"$branch1" ids --
    # so one legend row's hover reaches every piece of a grouped
    # dataflow, not just one.
    diagram_ids = doc.root.get_elements("//g[@class='asd-dataflow']").map { |g| g.attributes["data-dataflow"] }

    assert_equal ["provision_vm"] * 3, diagram_ids

    legend_ids = doc.root.get_elements("//g[@class='asd-legend-dataflow']").map { |g| g.attributes["data-dataflow"] }

    assert_equal ["provision_vm"], legend_ids

    assert_includes svg,
                    'svg:has(.asd-legend-dataflow[data-dataflow="provision_vm"]:hover) ' \
                    '.asd-dataflow[data-dataflow="provision_vm"] .asd-dataflow-line'
  end

  def test_renders_a_hop_group_s_shared_prefix_once_and_each_branch_as_its_own_labeled_segment
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "d" { }
      dataflow "flow" {
        hop "a"
        hop "b"
        hop group {
          branch { hop "c"; label "to c" }
          branch { hop "d"; label "to d" }
        }
        color "#8E44AD"
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60),
      "c" => Archsight::Diagram::Layout::Box.new(400, 0, 100, 60),
      "d" => Archsight::Diagram::Layout::Box.new(400, 200, 100, 60)
    }
    layout = Archsight::Diagram::Layout.attach_legend(graph, Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 300))

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    colored = doc.root.get_elements("//path[not(ancestor::marker)]").select { |p| p.attributes["class"]&.split&.include?("asd-dataflow-line") }

    # One shared "a -> b" trunk plus one segment per branch -- 3 colored
    # paths total, not 2 (one per branch) each redrawing "a -> b" too.
    assert_equal 3, colored.length
    colored.each { |p| assert_includes p.attributes["class"], "asd-dataflow-color-8E44AD" }

    # Only the legend gets one row for the whole dataflow, not one per branch.
    texts = doc.root.get_elements("//text").map(&:text)

    assert_includes texts, "to c"
    assert_includes texts, "to d"
    legend_labels = doc.root.get_elements("//text").map(&:text).grep(/\Aflow\z/)

    assert_equal ["flow"], legend_labels

    # Each branch's route is independently computed against the shared
    # "b" box, so without reconciliation it could pick a different exit
    # point than the trunk's own arrival point -- both branches must
    # start from that exact same point for the fork to read as one line
    # splitting, not two disconnected ones.
    routed = Archsight::Diagram::DataflowRouting.new(graph, boxes).compute_routes([])
    trunk = routed.find { |r| r[:dataflow].id == "flow$prefix" }
    branches = routed.select { |r| r[:dataflow].id.start_with?("flow$branch") }

    assert_equal 2, branches.length
    branches.each { |b| assert_equal trunk.points.last, b.points.first }
  end

  def test_shows_a_hop_group_s_label_once_on_the_shared_trunk_when_every_branch_agrees_on_it
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "d" { }
      dataflow "flow" {
        hop "a"
        hop "b"
        hop group {
          hop "c"
          hop "d"
        }
        color "#8E44AD"
        label "vm"
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60),
      "c" => Archsight::Diagram::Layout::Box.new(400, 0, 100, 60),
      "d" => Archsight::Diagram::Layout::Box.new(400, 200, 100, 60)
    }
    layout = Archsight::Diagram::Layout.attach_legend(graph, Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 300))

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)

    # One "vm" on the diagram's own line (font-size 11, the dataflow-label
    # size) plus one in the legend (font-size 12) -- not one per branch.
    vm_texts = doc.root.get_elements("//text").select { |t| t.text == "vm" }
    font_sizes = vm_texts.map { |t| t.attributes["class"][/asd-fs-(\d+)/, 1] }

    assert_equal %w[11 12], font_sizes.sort
  end

  def test_dedupes_a_hop_group_s_label_by_majority_not_unanimity_keeping_a_differing_branch_s_own_label
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "d" { }
      dataflow "flow" {
        hop "a"
        hop group {
          hop "b"
          hop "c"
          branch { hop "d"; label "different" }
        }
        color "#8E44AD"
        label "Events"
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 100, 60),
      "b" => Archsight::Diagram::Layout::Box.new(200, 0, 100, 60),
      "c" => Archsight::Diagram::Layout::Box.new(200, 200, 100, 60),
      "d" => Archsight::Diagram::Layout::Box.new(400, 400, 100, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 600, height: 500)

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    diagram_texts = doc.root.get_elements("//text").select { |t| t.attributes["class"]&.include?("asd-fs-11") }.map(&:text)

    # "b" and "c" share the majority label ("Events") and get deduplicated
    # to one instance; "d"'s own distinct label survives untouched.
    assert_equal %w[Events different], diagram_texts.sort
  end

  def test_grows_a_label_s_estimated_bounding_box_with_its_line_count_not_just_its_longest_line
    # Regression test: label_bbox used to assume a single line of text
    # regardless of how many `\n`-separated lines the label actually had,
    # underestimating a multi-line label's true vertical extent enough
    # that two multi-line labels could overlap undetected by the
    # placement's overlap-avoidance scoring.
    one_line = Archsight::Diagram::Renderer::LabelPlacer.label_bbox(0, 0, "one line", 11)
    three_lines = Archsight::Diagram::Renderer::LabelPlacer.label_bbox(0, 0, "one line\ntwo line\nthree line", 11)

    assert_operator three_lines[:bottom] - three_lines[:top], :>, (one_line[:bottom] - one_line[:top])
    # A single line's box is unchanged by the fix (n == 1 reduces to the
    # original one-line box exactly).
    assert_equal({ left: -26.0, right: 26.0, top: -14.3, bottom: 0.0 }, one_line)
  end

  def test_places_a_label_off_the_stretch_another_line_runs_alongside
    own = [[0.0, 100.0], [400.0, 100.0]]
    # Runs 15px above `own` along its first 230px -- through where the
    # label's preferred 0.35 spot (x=140) would sit.
    other = [[0.0, 85.0], [230.0, 85.0]]
    unaware = Archsight::Diagram::Renderer::LabelPlacer.new({})
    aware = Archsight::Diagram::Renderer::LabelPlacer.new({})
    aware.register_paths([own, other])

    assert_equal [140.0, 100.0], unaware.place_label_along(own, "calls")
    assert_equal [260.0, 100.0], aware.place_label_along(own, "calls") # the 0.65 spot, clear of `other`
  end

  def test_places_a_label_away_from_a_container_s_border_but_happily_well_inside_one
    own = [[0.0, 100.0], [400.0, 100.0]]
    around = Archsight::Diagram::Renderer::LabelPlacer.new({}, containers: { "g" => Archsight::Diagram::Layout::Box.new(200, 100, 400, 200) })
    # A border at x=150, right where the 0.35 spot's label (x 124..156) would sit.
    straddled = Archsight::Diagram::Renderer::LabelPlacer.new({}, containers: { "g" => Archsight::Diagram::Layout::Box.new(275, 100, 250, 200) })

    assert_equal [140.0, 100.0], around.place_label_along(own, "calls")
    assert_equal [260.0, 100.0], straddled.place_label_along(own, "calls")
  end

  def test_places_a_label_off_its_own_line_s_bend
    # The 0.35 spot (y=114 on the vertical leg) sits right at the corner,
    # with the horizontal leg running through the label too.
    own = [[0.0, 100.0], [140.0, 100.0], [140.0, 400.0]]

    assert_equal [140.0, 246.0], Archsight::Diagram::Renderer::LabelPlacer.new({}).place_label_along(own, "calls")
  end

  def test_keeps_a_label_clear_of_an_edge_declared_after_its_own
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "d" { }
      a -> b { label "calls"; style "straight" }
      c -> d { style "straight" }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(60, 300, 100, 40),
      "b" => Archsight::Diagram::Layout::Box.new(560, 300, 100, 40),
      "c" => Archsight::Diagram::Layout::Box.new(250, 500, 100, 40),
      "d" => Archsight::Diagram::Layout::Box.new(250, 100, 100, 40)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 700, height: 600)

    svg = Archsight::Diagram::Renderer.render(graph, layout)

    # a -> b runs x 110..510 at y=300; c -> d crosses it at x=250, exactly
    # its 0.35 spot -- drawn later, but known before any label is placed.
    assert_includes svg, %(<text id="asd-edge-a__b__label" x="370.00" y="294.00")
  end

  def test_gives_every_edge_an_invisible_hover_target_along_its_own_line_and_marks_its_hover_sources
    source = <<~SRC
      group "g" {
        component "a" { }
      }
      component "b" { }
      component "c" { }
      a -> b { label "x" }
      g -> c
      b -> c { relation "implements" }
      a -> c { relation "implements" }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))
    edges = REXML::XPath.match(doc, "//g[@data-asd-kind='edge']")

    assert_equal 4, edges.length
    edges.each do |g|
      id = g.attributes["id"]

      assert_equal "asd-edge", g.attributes["class"]
      assert_equal REXML::XPath.first(g, "path[@id='#{id}__line']").attributes["d"],
                   REXML::XPath.first(g, "path[@id='#{id}__hit']").attributes["d"]
    end
    assert_includes REXML::XPath.first(doc, "//text[@id='asd-edge-a__b__label']").attributes["class"].split, "asd-edge-label"
    assert_equal "asd-hover-source", REXML::XPath.first(doc, "//g[@id='asd-node-a']").attributes["class"]
    assert_includes REXML::XPath.first(doc, "//rect[@id='asd-node-g__frame']").attributes["class"].split, "asd-hover-source"
    assert_nil REXML::XPath.first(doc, "//g[@id='asd-node-c']").attributes["class"]
    assert_includes REXML::XPath.first(doc, "//path[@id='asd-tree-c__trunk']").attributes["class"].split, "asd-tree-line"
  end

  def test_keeps_the_dp_cp_view_and_ic_api_server_labels_off_their_neighbours_lines
    {
      "dp_cp_view" => %w[asd-edge-saas_cp__slim_cp asd-edge-customer__saas_api],
      "ic_api_server" => %w[asd-edge-quota__quota_system asd-edge-prometheus__http_server_bottom]
    }.each do |example, owners|
      source = File.read(File.expand_path("fixtures/#{example}.asd", __dir__))
      doc = REXML::Document.new(Archsight::Diagram.render(source, relation_filter: Archsight::Diagram::Relations.names))

      owners.each do |owner|
        assert_empty foreign_lines_near_label(doc, owner), "#{example}: #{owner}'s label sits on or beside another line"
      end
    end
  end

  def test_keeps_two_long_multi_line_dataflow_labels_from_overlapping_each_other
    source = <<~SRC
      component "a" { }
      component "b" { }
      component "c" { }
      component "d" { }
      dataflow "flow1" {
        hop "a"
        hop "b"
        label "token exchange /\\nscoped identity creation /\\ngroup & role assignment"
        color "#4A5568"
      }
      dataflow "flow2" {
        hop "c"
        hop "d"
        label "manage policy\\nand policy assignment"
        color "#b85450"
      }
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    boxes = {
      "a" => Archsight::Diagram::Layout::Box.new(0, 0, 120, 60),
      "b" => Archsight::Diagram::Layout::Box.new(300, 60, 120, 60),
      "c" => Archsight::Diagram::Layout::Box.new(0, 80, 120, 60),
      "d" => Archsight::Diagram::Layout::Box.new(300, 140, 120, 60)
    }
    layout = Archsight::Diagram::Layout::Result.new(boxes: boxes, width: 500, height: 250)

    svg = Archsight::Diagram::Renderer.render(graph, layout)
    doc = REXML::Document.new(svg)
    labels = doc.root.get_elements("//text[contains(@class,'asd-fs-11')]")

    assert_equal 2, labels.length

    bboxes = labels.map do |t|
      lines = t.get_elements("tspan").map(&:text)
      text = lines.empty? ? t.text : lines.join("\n")
      Archsight::Diagram::Renderer::LabelPlacer.label_bbox(t.attributes["x"].to_f, t.attributes["y"].to_f, text, 11)
    end

    assert_same false, Archsight::Diagram::Renderer::LabelPlacer.rects_intersect?(*bboxes)
  end

  # link

  def test_link_wraps_a_linked_leaf_s_shape_and_label_each_in_their_own_a_href
    source = %(component "a" { label "A"; link "https://example.com" }\n)
    doc = REXML::Document.new(Archsight::Diagram.render(source))

    anchors = doc.root.get_elements("//a")

    assert_equal 2, anchors.length # one around the rect, one around the text
    anchors.map { |a| a.attributes["href"] }.each { |href| assert_equal "https://example.com", href }
    anchors.map { |a| a.attributes["class"] }.each { |cls| assert_equal "asd-link", cls }
    assert_equal 1, doc.root.get_elements("//a/rect").length
    assert_equal 1, doc.root.get_elements("//a/text").length
  end

  def test_link_adds_no_a_at_all_for_a_node_without_a_link
    doc = REXML::Document.new(Archsight::Diagram.render(%(component "a" { label "A" }\n)))

    assert_empty doc.root.get_elements("//a")
  end

  def test_link_wraps_a_linked_container_s_box_and_title_too
    source = <<~SRC
      group "g" { label "G"; link "https://example.com/g"; component "a" { } }
    SRC
    doc = REXML::Document.new(Archsight::Diagram.render(source))
    anchors = doc.root.get_elements("//a")

    assert_equal 2, anchors.length
    anchors.map { |a| a.attributes["href"] }.each { |href| assert_equal "https://example.com/g", href }
  end

  # inline markdown-lite

  def test_inline_markdown_lite_renders_bold_italic_and_underline_as_own_tspans_and_plain_text_unwrapped
    source = %(component "a" { label "**b** *i* __u__ plain" }\n)
    svg = Archsight::Diagram.render(source)

    assert_includes svg, '<tspan class="asd-run-bold">b</tspan>'
    assert_includes svg, '<tspan class="asd-run-italic">i</tspan>'
    assert_includes svg, '<tspan class="asd-run-underline">u</tspan>'
    assert_includes svg, " plain</text>" # trailing plain text stays bare, no tspan
  end

  def test_inline_markdown_lite_keeps_a_tinted_container_s_markdown_in_its_legend_swatch_row
    svg = Archsight::Diagram.render(%(group "g" { label "**Hot** zone"; tint "red"; component "a" { } }\nlegend "bottom"\n))

    assert_includes svg, 'data-asd-owner="asd-legend-swatch-Group_Hot_zone">Group <tspan class="asd-run-bold">Hot</tspan> zone</text>'
  end

  def test_inline_markdown_lite_renders_a_plain_label_with_no_markdown_identically_to_before_markdown_support
    svg = Archsight::Diagram.render(%(component "a" { label "Just a label" }\n))

    assert_includes svg, ">Just a label</text>"
    refute_includes svg, "<tspan"
  end

  def test_inline_markdown_lite_renders_an_inline_text_url_link_as_its_own_nested_a_href
    svg = Archsight::Diagram.render(%(component "a" { label "see [the docs](https://example.com/docs)" }\n))

    assert_includes svg, '<a href="https://example.com/docs" class="asd-link">'
    assert_includes svg, '<tspan class="asd-run-underline">the docs</tspan>'
  end

  def test_inline_markdown_lite_suppresses_the_inline_link_s_own_a_when_the_node_itself_already_has_a_link
    source = %(component "a" { label "[click](https://example.com/inner)"; link "https://example.com/outer" }\n)
    doc = REXML::Document.new(Archsight::Diagram.render(source))

    text_anchor = doc.root.get_elements("//a[@href='https://example.com/outer']/text").first

    refute_nil text_anchor
    # the inline link's own <a> must not appear nested inside the node-level one
    assert_empty text_anchor.get_elements(".//a")
    assert_includes text_anchor.to_s, "click" # styling (underline) still applied via tspan
  end

  def test_inline_markdown_lite_supports_markdown_inside_an_edge_label_and_a_container_title_too
    source = <<~SRC
      boundary "b" { label "**Bold Boundary**" }
      component "a" { }
      component "c" { }
      a -> c { label "*fast* path" }
    SRC
    svg = Archsight::Diagram.render(source)

    assert_includes svg, '<tspan class="asd-run-bold">Bold Boundary</tspan>'
    assert_includes svg, '<tspan class="asd-run-italic">fast</tspan>'
  end

  # multi-line labels

  def test_multi_line_labels_renders_each_line_as_its_own_centered_tspan
    svg = Archsight::Diagram.render(%(component "a" { label "First\\nSecond" }\n))

    assert_match(%r{<tspan x="[\d.]+" dy="-[\d.]+">First</tspan><tspan x="[\d.]+" dy="[\d.]+">Second</tspan>}, svg)
  end

  def test_renders_with_the_file_s_theme_unless_the_caller_overrides_it
    source = %(theme "compact"\ngroup "g" { component "a" { label "A" } }\n)
    compact_svg = Archsight::Diagram.render(source)
    default_svg = Archsight::Diagram.render(source, theme: "default")

    assert_includes compact_svg, "asd-fs-11" # node label and group title at the compact size
    refute_includes compact_svg, ".asd-fs-15"
    assert_includes default_svg, ".asd-fs-15"
    assert_operator svg_width(compact_svg), :<, svg_width(default_svg)
  end

  def test_routes_bridges_into_the_same_box_on_separate_parallel_lanes
    source = <<~SRC
      layer "row" {
        component "a" { }
        component "b" { }
        component "c" { }
        component "d" { }
      }
      a -> c
      a -> d
      b -> d
    SRC
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    renderer = Archsight::Diagram::Renderer.new(graph, Archsight::Diagram::Layout.compute(graph))
    routing = renderer.instance_variable_get(:@edge_routing)
    paths = routing.compute_paths(renderer.send(:individually_routed_edges))
    routing.refine_line_overlap!(paths)
    routing.separate_bridge_lanes!(paths)
    routing.assign_ports!(paths) # as `render` does: spreads the two entries into `d` apart

    into_d = paths.select { |ep| ep.edge.to.id == "d" }.map { |ep| ep.points[2][1] } # each bridge's loop line

    assert_equal 2, into_d.uniq.length
    assert_operator (into_d.first - into_d.last).abs, :>=, Archsight::Diagram::EdgeRouter::BridgePath::BRIDGE_LANE_SPACING
    assert_in_delta 0.0, paths.combination(2).sum { |x, y| Archsight::Diagram::EdgeRouter::PathMetrics.overlap_length(x.points, [y.points]) }, 0.01
  end

  def test_keeps_two_endpoints_apart_when_one_of_them_cannot_move_off_its_routed_port
    target = Archsight::Diagram::Layout::Box.new(100, 100, 100, 60) # right side x=150, y 70..130
    # A small box just below `pinned`'s line: shifting that line's end down
    # its side, the only way its slot lies, would drag it through this.
    blocker = Archsight::Diagram::Layout::Box.new(160, 125.5, 10, 19)
    pinned = Archsight::Diagram::EdgeRouting::RoutedEdge.new(
      points: [[300.0, 250.0], [150.0, 100.0]], from_box: Archsight::Diagram::Layout::Box.new(350, 250, 100, 60),
      to_box: target, obstacles: [blocker]
    )
    # Arrives from above `pinned`, so it's slotted first -- right onto
    # `pinned`'s own point, were `pinned` assumed to move away.
    other = Archsight::Diagram::EdgeRouting::RoutedEdge.new(
      points: [[300.0, 150.0], [150.0, 112.0]], from_box: Archsight::Diagram::Layout::Box.new(350, 150, 100, 60),
      to_box: target, obstacles: []
    )

    Archsight::Diagram::EdgeRouting.new(nil, {}).assign_ports!([pinned, other])

    assert_equal [150.0, 100.0], pinned.points.last
    assert_operator (other.points.last[1] - pinned.points.last[1]).abs, :>=, Archsight::Diagram::EdgeRouting::PORT_MIN_GAP
  end

  def test_moves_both_ends_of_one_line_that_starts_and_ends_on_the_same_side
    box = Archsight::Diagram::Layout::Box.new(100, 100, 100, 60) # right side x=150, y 70..130
    loop_path = Archsight::Diagram::EdgeRouting::RoutedEdge.new(
      points: [[150.0, 100.0], [190.0, 100.0], [190.0, 100.0], [150.0, 100.0]], from_box: box, to_box: box, obstacles: []
    )

    Archsight::Diagram::EdgeRouting.new(nil, {}).assign_ports!([loop_path])

    start_y = loop_path.points.first[1]
    end_y = loop_path.points.last[1]

    refute_in_delta 100.0, start_y, 0.01
    refute_in_delta 100.0, end_y, 0.01
    assert_operator (start_y - end_y).abs, :>=, Archsight::Diagram::EdgeRouting::PORT_MIN_GAP
  end

  def test_routes_the_dp_cp_view_example_s_edges_outside_their_own_boxes_on_ports_of_their_own
    source = File.read(File.expand_path("fixtures/dp_cp_view.asd", __dir__))
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    renderer = Archsight::Diagram::Renderer.new(graph, Archsight::Diagram::Layout.compute(graph))
    routing = renderer.instance_variable_get(:@edge_routing)
    paths = routing.compute_paths(renderer.send(:individually_routed_edges))
    routing.refine_line_overlap!(paths)
    routing.separate_bridge_lanes!(paths)
    routing.assign_ports!(paths)
    metrics = Archsight::Diagram::EdgeRouter::PathMetrics

    paas_to_iaas = paths.find { |ep| ep.edge.from.id == "paas_cp" && ep.edge.to.id == "iaas_cp" }

    refute metrics.enters_interior?(paas_to_iaas.points, paas_to_iaas.from_box)
    refute metrics.enters_interior?(paas_to_iaas.points, paas_to_iaas.to_box)

    # The undercloud (slim_cp's boundary) is declared last, so it sits to
    # the right of the other layers and their edges share its left side.
    into_slim_cp = paths.select { |ep| ep.edge.to.id == "slim_cp" && ep.to_box.side_of(ep.points.last) == :left }.map { |ep| ep.points.last[1] }

    assert_operator into_slim_cp.length, :>=, 2
    into_slim_cp.combination(2).each do |y1, y2|
      assert_operator (y1 - y2).abs, :>=, Archsight::Diagram::EdgeRouting::PORT_MIN_GAP
    end
  end

  def test_grows_the_canvas_past_its_own_edge_to_fit_a_bridge_on_an_outer_lane
    source = %(layer {\n component "a" { }\n component "b" { }\n component "c" { }\n component "d" { }\n}\na -> c\na -> d\nb -> d\n)
    svg = Archsight::Diagram.render(source)
    min_x, min_y, width, height = svg[/viewBox="([^"]*)"/, 1].split.map(&:to_f)
    line_ys = svg.scan(/<path [^>]*?d="([^"]*)"/).flatten.flat_map { |d| d.scan(/-?[\d.]+ (-?[\d.]+)/).flatten.map(&:to_f) }

    assert_operator min_y, :<, 0.0 # an outer lane loops above the boxes' own canvas
    assert_operator line_ys.min, :>=, min_y
    assert_operator line_ys.max, :<=, min_y + height
    assert_in_delta 0.0, min_x, 0.01
    assert_includes svg, %(<rect id="asd-canvas-bg" x="0" y="#{format("%.2f", min_y)}" width="#{format("%.2f", width)}")
  end

  private

  # Every `tag` drawn for a node, edge or the legend -- i.e. everything
  # but `<defs>` content and dataflows (each in its own `<g>`), which is
  # what `doc.root.get_elements(tag)` matched back when nodes/edges weren't
  # wrapped in `<g>`s of their own yet -- and never an edge's invisible
  # hover target (`.asd-hit`), which isn't drawn at all.
  def drawn(doc, tag)
    REXML::XPath.match(doc, "//#{tag}[not(ancestor::defs) and not(@class='asd-hit') and " \
                            "not(ancestor::g[@class='asd-dataflow' or @class='asd-legend-dataflow'])]")
  end

  # let(:source) from the "style:" describe block
  def source = @source ||= %(component "a" { label "A" }\n)

  def turn_angle(a, b, c)
    Archsight::Diagram::Geometry.turn_angle_degrees(a, b, c)
  end

  def svg_width(svg) = svg[/<svg[^>]* width="([\d.]+)"/, 1].to_f

  # The ids of every other edge/dataflow line crossing, or passing within
  # `LabelPlacer::LABEL_PATH_CLEARANCE` of, `owner`'s label.
  def foreign_lines_near_label(doc, owner)
    placer = Archsight::Diagram::Renderer::LabelPlacer
    label = REXML::XPath.first(doc, "//text[@id='#{owner}__label']")
    spans = label.get_elements("tspan")
    text = spans.empty? ? label.text : spans.map(&:text).join("\n")
    box = placer.label_bbox(label.attributes["x"].to_f, label.attributes["y"].to_f, text, label.attributes["class"][/asd-fs-(\d+)/, 1].to_i)
    c = placer::LABEL_PATH_CLEARANCE
    near = placer::Rect.new(box[:left] - c, box[:right] + c, box[:top] - c, box[:bottom] + c)

    REXML::XPath.match(doc, "//path[contains(@id,'__line')]").filter_map do |path|
      id = path.attributes["id"].delete_suffix("__line")
      next if id == owner

      points = path.attributes["d"].scan(/-?[\d.]+/).map(&:to_f).each_slice(2).to_a
      id if points.each_cons(2).any? { |(x1, y1), (x2, y2)| Archsight::Diagram::EdgeRouter::PathMetrics.segment_crosses_box?(x1, y1, x2, y2, near) }
    end
  end
end
