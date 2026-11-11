# frozen_string_literal: true

require_relative "../test_helper"
require "rexml/document"
require "archsight/diagram/formatter"

# Ports (`port "id" { ... }` tabs on a leaf that edges attach to with `leaf.id`), badges, `line` styles,
# `align`, a leaf's `no-extend` + `anchor`, and inline `code` in labels.
class DiagramPortsTest < Minitest::Test
  Diagram = Archsight::Diagram

  def build(source) = Diagram::Graph.build(Diagram::Parser.parse(source))

  def build_error(source)
    assert_raises(Diagram::Error) { build(source) }.message
  end

  def layout(source) = Diagram::Layout.compute(build(source))

  def svg(source) = REXML::Document.new(Diagram.render(source))

  HUB = <<~ASD
    stack {
      layer {
        component "a" { label "client a" }
        component "b" { label "client b" }
      }
      component "hub" {
        label "a wide hub in the middle of everything"
        port "tcp" { label "tcp :80"; side "top" }
        port "sock" { label "unix hub.sock"; side "top" }
      }
    }
    a -> hub.tcp
    b -> hub.sock
  ASD

  # --- parsing and the graph ------------------------------------------------

  def test_an_edge_names_a_port_as_node_dot_port
    graph = build(HUB)
    edge = graph.edges.first

    assert_equal "hub", edge.to.id
    assert_equal "tcp", edge.to_port.id
    assert_nil edge.from_port
    assert_equal %w[tcp sock], graph.node("hub").ports.map(&:id)
  end

  def test_a_node_whose_whole_id_has_a_dot_wins_over_a_port
    graph = build(%(component "a" { }\ncomponent "b.p" { }\ncomponent "b" { port "p" { } }\na -> b.p\n))

    assert_equal "b.p", graph.edges.first.to.id
    assert_nil graph.edges.first.to_port
  end

  def test_an_unknown_port_names_the_ports_the_node_has
    message = build_error(HUB.sub("a -> hub.tcp", "a -> hub.tpc"))

    assert_match(/unknown port "tpc" on "hub" \(its ports: tcp, sock\) \(edge at line/, message)
  end

  def test_ports_only_sit_on_box_shaped_leaves
    assert_match(/only a leaf .* has ports, not group "g"/, build_error(%(group "g" { port "p" { } }\n)))
    assert_match(/ports need a box-shaped leaf .*not shape "circle"/, build_error(%(api "a" { port "p" { } }\n)))
    assert_match(/cannot contain nested blocks/, build_error(%(component "a" { port "p" { } component "b" { } }\n)))
  end

  def test_port_attributes_are_checked
    assert_match(/unknown side "up" on port "p"/, build_error(%(component "a" { port "p" { side "up" } }\n)))
    assert_match(/unknown attribute "color" on port "p"/, build_error(%(component "a" { port "p" { color "x" } }\n)))
    assert_match(/at "top" on port "p" .* does not lie along its top side/, build_error(%(component "a" { port "p" { at "top" } }\n)))
    assert_match(/duplicate port "p" on "a"/, build_error(%(component "a" { port "p" { } port "p" { } }\n)))
    assert build(%(component "a" { port "p" { side "left"; at "25%" } }\n))
  end

  def test_a_dataflow_hop_cannot_be_a_port
    message = build_error(%(component "a" { port "p" { } }\ncomponent "b" { }\ndataflow "f" { hop "a.p"; hop "b" }\n))

    assert_match(/"a.p" is a port of "a"; only edges attach to ports/, message)
  end

  def test_badges_name_a_top_level_definition
    graph = build(%(badge "beta" { tint "orange"; label "beta only" }\ncomponent "a" { badge "beta"; port "p" { badge "beta" } }\n))

    assert_equal "orange", graph.badge_definition("beta").tint
    assert_match(/unknown badge "btea" on component "a" \(line 2\) -- did you mean "beta"\?/,
                 build_error(%(badge "beta" { }\ncomponent "a" { badge "btea" }\n)))
    assert_match(/define it at the top level/, build_error(%(component "a" { badge "x" }\n)))
    assert_match(/unknown tint "bleu" on badge "x"/, build_error(%(badge "x" { tint "bleu" }\n)))
  end

  def test_line_styles_and_their_legend_text
    graph = build(%(line "dashed" { label "read at start" }\ncomponent "a" { }\ncomponent "b" { }\na -> b { line "dashed" }\n))

    assert_equal "dashed", graph.edges.first.line_style
    assert_equal "read at start", graph.line_definition("dashed").label
    assert_match(/unknown line "wavy" on edge/, build_error(%(component "a" { }\ncomponent "b" { }\na -> b { line "wavy" }\n)))
    assert_match(/unknown line style "solid"/, build_error(%(line "solid" { }\n)))
    assert_match(/line "dashed" already defined/, build_error(%(line "dashed" { label "x" }\nline "dashed" { label "y" }\n)))
  end

  def test_align_names_another_node
    assert_match(/align "nope" on component "a" .* names no node/, build_error(%(component "a" { align "nope" }\n)))
    assert_match(/names the node itself/, build_error(%(component "a" { align "a" }\n)))
    assert_match(/names a node it is nested with/, build_error(%(group "g" { component "a" { align "g" } }\n)))
  end

  def test_a_leaf_anchor_needs_no_extend
    assert_match(/only places a leaf that keeps its own size: add no-extend/, build_error(%(component "a" { anchor "left" }\n)))
    assert build(%(component "a" { anchor "left"; no-extend }\n))
  end

  def test_a_definition_keyword_is_still_usable_as_a_node_id_in_an_edge
    graph = build(%(component "line" { }\ncomponent "badge" { }\nline -> badge\n))

    assert_equal %w[line badge], [graph.edges.first.from.id, graph.edges.first.to.id]
  end

  # --- includes and the formatter ---------------------------------------------

  def test_a_namespaced_include_prefixes_port_references_and_align
    files = { "part" => %(component "s" { port "p" { } }\ncomponent "t" { align "s, top s" }\nt -> s.p\n) }
    result = Diagram.expand(%(include "part" { namespace "x" }\n), includes: ->(path) { files.fetch(path) })
    graph = Diagram::Graph.build(result.statements)

    assert_equal "x.s", graph.edges.first.to.id
    assert_equal "p", graph.edges.first.to_port.id
    assert_equal "x.s, top x.s", graph.node("x.t").align
  end

  def test_definitions_in_a_container_level_include_are_dropped_with_a_warning
    files = { "part" => %(badge "b" { }\ncomponent "s" { }\n) }
    result = Diagram.expand(%(group "g" { include "part" }\n), includes: ->(path) { files.fetch(path) })

    assert_match(/the badge "b" .* is ignored/, result.warnings.first)
  end

  def test_the_same_definition_twice_is_fine
    assert build(%(badge "b" { tint "red" }\nbadge "b" { tint "red" }\n))
  end

  def test_the_formatter_keeps_ports_and_definitions
    source = %(badge "b" { tint "red" }\ncomponent "a" {\nport "p" { side "top" }\n}\n)

    assert_equal %(badge "b" { tint "red" }\ncomponent "a" {\n  port "p" { side "top" }\n}\n), Diagram::Formatter.format(source)
  end

  # --- layout ---------------------------------------------------------------

  def test_a_port_lines_up_with_the_node_its_edge_comes_from
    result = layout(HUB)
    tcp = result.ports.fetch("hub.tcp")
    hub = result.boxes["hub"]

    assert_in_delta result.boxes["a"].x, tcp.x, 0.5
    assert_in_delta hub.top, tcp.y, 0.01
    assert_in_delta result.boxes["b"].x, result.ports.fetch("hub.sock").x, 0.5
  end

  def test_tabs_on_one_side_never_overlap
    result = layout(%(component "a" { }\ncomponent "n" { port "p" { label "long label one" } port "q" { label "long label two" } }\na -> n.p\na -> n.q\n))
    p, q = result.ports.values_at("n.p", "n.q").sort_by(&:x)

    assert_operator p.right + Diagram::Layout::PortMetrics::GAP, :<=, q.left + 0.01
  end

  def test_a_leaf_grows_to_hold_its_tabs
    plain = layout(%(component "n" { label "n" }\n)).boxes["n"]
    ported = layout(%(component "n" { label "n"; port "p" { label "a rather long port label" } port "q" { label "another long one" } }\n)).boxes["n"]

    assert_operator ported.width, :>, plain.width
  end

  def test_at_pins_a_port_and_side_puts_it_on_that_side
    result = layout(%(component "n" { label "a fairly wide node to place ports on"; port "l" { side "bottom"; at "left" } port "r" { side "right"; at "top" } }\n))
    box = result.boxes["n"]
    left = result.ports.fetch("n.l")
    right = result.ports.fetch("n.r")

    assert_in_delta box.bottom, left.y, 0.01
    assert_in_delta box.left + Diagram::Layout::PortMetrics::MARGIN + (left.width / 2.0), left.x, 0.01
    assert_in_delta box.right, right.x, 0.01
  end

  def test_a_port_without_a_side_faces_its_peer
    result = layout(%(stack {\ncomponent "n" { label "n"; port "p" { } }\ncomponent "below" { }\n}\nn.p -> below\n))

    assert_in_delta result.boxes["n"].bottom, result.ports.fetch("n.p").y, 0.01
  end

  def test_tabs_widen_the_gap_between_the_ranks_they_face
    plain = layout(%(stack {\ncomponent "a" { }\ncomponent "b" { }\n}\n)).boxes
    ported = layout(%(stack {\ncomponent "a" { }\ncomponent "b" { port "p" { side "top" } }\n}\n)).boxes

    assert_in_delta (ported["b"].top - ported["a"].bottom) - (plain["b"].top - plain["a"].bottom),
                    Diagram::Layout::PortMetrics.new(Diagram::Theme::DEFAULT).height / 2.0, 0.01
  end

  def test_align_centers_a_node_under_another_container_s_node
    source = <<~ASD
      stack {
        layer {
          component "left" { label "left one" }
          component "right" { label "right one" }
        }
        layer {
          component "under" { label "u"; align "right"; no-extend }
        }
      }
    ASD
    boxes = layout(source).boxes

    assert_in_delta boxes["right"].x, boxes["under"].x, 0.5
  end

  def test_align_stops_at_the_edge_of_its_row
    source = <<~ASD
      stack {
        layer {
          component "left" { label "the left one, rather wide" }
          component "right" { label "r" }
        }
        component "under" { label "wider than the right one"; align "right"; no-extend }
      }
    ASD
    boxes = layout(source).boxes

    assert_in_delta boxes["right"].right, boxes["under"].right, 0.5
    assert_operator boxes["under"].x, :<, boxes["right"].x
  end

  COLUMNS = <<~ASD
    layer {
      stack {
        component "a1" { label "a one"; no-extend }
        component "a2" { label "a two" }
        component "a3" { label "a three" }
      }
      stack {
        component "b1" { label "b one" }
        component "b2" { label "b two" }
      }
    }
  ASD

  def test_align_top_lines_up_tops_across_columns
    boxes = layout(COLUMNS.sub(%(component "b2" { label "b two" }), %(component "b2" { label "b two"; align "top a3" }))).boxes

    assert_in_delta boxes["a3"].top, boxes["b2"].top, 0.5
    assert_operator boxes["b1"].bottom, :<, boxes["b2"].top
  end

  def test_align_in_a_stack_pushes_the_rank_before_it_when_it_comes_too_close
    boxes = layout(COLUMNS.sub(%(component "b2" { label "b two" }), %(component "b2" { label "b two"; align "top a1" }))).boxes

    assert_operator boxes["b2"].top, :>, boxes["a1"].top # b1 is in the way at the top of the column
    assert_operator boxes["b1"].bottom, :<, boxes["b2"].top # and keeps its (tight stack) gap
  end

  def test_align_takes_one_entry_per_axis
    boxes = layout(COLUMNS.sub(%(component "b2" { label "b two" }), %(component "b2" { label "b"; no-extend; align "left b1, bottom a3" }))).boxes

    assert_in_delta boxes["b1"].left, boxes["b2"].left, 0.5
    assert_in_delta boxes["a3"].bottom, boxes["b2"].bottom, 0.5
  end

  def test_align_entries_are_checked
    assert_match(/unknown edge "topp" in align "topp b"/, build_error(%(component "a" { align "topp b" }\ncomponent "b" { }\n)))
    assert_match(/lines up left and right on one axis/, build_error(%(component "a" { align "left b, right b" }\ncomponent "b" { }\n)))
    assert_match(/names no node "right"/, build_error(%(component "a" { align "right" }\n)))
    assert_equal [[:x, "center", "top"]], build(%(component "a" { align "top" }\ncomponent "top" { }\n)).node("a").alignments
  end

  def test_no_extend_keeps_a_leaf_s_own_width_in_a_stack_at_its_anchor
    source = %(stack {\ncomponent "wide" { label "a really rather wide component" }\ncomponent "small" { label "s"; no-extend; anchor "right" }\n}\n)
    boxes = layout(source).boxes

    assert_operator boxes["small"].width, :<, boxes["wide"].width
    assert_in_delta boxes["wide"].right, boxes["small"].right, 0.5
  end

  def test_padding_widens_the_room_inside_a_container
    plain = layout(%(boundary "b" { component "a" { } }\n)).boxes
    padded = layout(%(boundary "b" { padding "200%"; component "a" { } }\n)).boxes
    theme = Diagram::Theme::DEFAULT

    assert_in_delta plain["b"].width + (2 * theme.padding), padded["b"].width, 0.01
    assert_in_delta padded["b"].left + (2 * theme.padding), padded["a"].left, 0.01
    assert_match(/invalid padding "wide"/, build_error(%(group "g" { padding "wide" }\n)))
  end

  # --- routing and rendering --------------------------------------------------

  def test_an_edge_to_a_port_ends_on_the_outer_side_of_its_tab
    doc = svg(HUB)
    tab = REXML::XPath.first(doc, "//rect[@data-asd-port='tcp']")
    line = REXML::XPath.first(doc, "//g[@data-asd-to='hub'][@data-asd-from='a']//path[contains(@class, 'asd-line')]")
    last_y = line.attributes["d"].scan(/-?\d+(?:\.\d+)?/).last.to_f

    assert_in_delta tab.attributes["y"].to_f, last_y, 0.5
  end

  def test_edges_on_one_tab_spread_over_it
    source = HUB.sub("b -> hub.sock", "b -> hub.tcp")
    routing = Diagram::Layout.compute(graph = build(source)).then do |result|
      Diagram::EdgeRouting.new(graph, result.boxes, ports: result.ports).compute_paths(graph.edges).tap { |paths| Diagram::EdgeRouting.new(graph, result.boxes, ports: result.ports).assign_ports!(paths) }
    end
    ends = routing.map { |ep| ep.points.last.first }

    refute_in_delta ends.first, ends.last, 1.0
  end

  def test_renders_tabs_badges_dashed_lines_and_their_legend
    source = <<~ASD
      badge "beta" { tint "orange"; label "beta only" }
      line "dashed" { label "read at start" }
      component "a" { badge "beta" }
      component "b" { port "p" { label "tcp :80"; badge "beta" } }
      a -> b.p { line "dashed" }
    ASD
    doc = svg(source)

    assert REXML::XPath.first(doc, "//rect[contains(@class, 'asd-port')][@data-asd-port='p']")
    assert_equal 2, REXML::XPath.match(doc, "//g[starts-with(@id, 'asd-node')]//circle[contains(@class, 'asd-badge-orange')]").length
    assert REXML::XPath.first(doc, "//path[contains(@class, 'asd-line-dashed')]")
    assert REXML::XPath.first(doc, "//text[contains(@class, 'asd-port-text')]")
    legend = REXML::XPath.match(doc, "//g[starts-with(@id, 'asd-legend-')]").map { |g| g.attributes["id"] }

    assert_includes legend, "asd-legend-port"
    assert_includes legend, "asd-legend-line-dashed"
    assert_includes legend, "asd-legend-badge-beta"
  end

  def test_backticks_make_a_monospace_run_measured_with_mono_widths
    text = Diagram::MarkdownText.detect("run `iii` now")

    assert_equal [["run ", {}], ["iii", { code: true }], [" now", {}]], Diagram::TextMetrics.markdown_runs(text)
    assert_operator Diagram::TextMetrics.rendered_width(Diagram::MarkdownText.detect("`iii`"), font_size: 10),
                    :>, Diagram::TextMetrics.rendered_width("iii", font_size: 10)
    assert REXML::XPath.first(svg(%(component "a" { label "`ovs-vsctl` add-br" }\n)), "//tspan[@class='asd-run-code']")
  end

  def test_the_fixture_renders
    source = File.read(File.expand_path("fixtures/ports.asd", __dir__))

    assert_includes Diagram.render(source), "asd-port"
  end
end
