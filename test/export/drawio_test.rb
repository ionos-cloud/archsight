# frozen_string_literal: true

require "test_helper"
require "base64"
require "rexml/document"
require "archsight/diagram"
require "archsight/export/confluence/drawio"

class ConfluenceDrawioTest < Minitest::Test
  Drawio = Archsight::Export::Confluence::Drawio

  SVG = <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" width="200" height="120" viewBox="0 0 200 120">
      <rect id="frame" x="10" y="10" width="180" height="100"/>
      <a href="https://wiki.example.com/p?a=1&amp;b=2"><rect id="body" x="30" y="40" width="60" height="30"/></a>
      <a href="https://wiki.example.com/q"><ellipse cx="150" cy="60" rx="20" ry="10"/></a>
      <a href="https://wiki.example.com/p"><text x="1" y="1">label</text></a>
      <a href="https://wiki.example.com/r"><polygon points="100,20 120,20 110,40"/></a>
    </svg>
  SVG

  def test_the_svg_becomes_an_image_cell_of_the_same_size
    xml = Drawio.wrap_svg(SVG, "pic")
    doc = REXML::Document.new(xml)
    image = REXML::XPath.first(doc, "//mxCell[@id='2']")

    assert_includes image.attributes["style"], "shape=image"
    assert_equal "200", REXML::XPath.first(doc, "//mxCell[@id='2']/mxGeometry").attributes["width"]
    assert_equal "200", REXML::XPath.first(doc, "//mxGraphModel").attributes["pageWidth"]
    data = image.attributes["style"][%r{image=data:image/svg\+xml,([A-Za-z0-9+/=]+)}, 1]

    assert_includes Base64.decode64(data), "<rect id=\"body\""
  end

  def test_every_linked_shape_gets_an_invisible_clickable_shape_over_it
    doc = REXML::Document.new(Drawio.wrap_svg(SVG, "pic"))
    links = REXML::XPath.match(doc, "//UserObject")

    assert_equal(["https://wiki.example.com/p?a=1&b=2", "https://wiki.example.com/q", "https://wiki.example.com/r"], links.map { |l| l.attributes["link"] })
    first = REXML::XPath.first(links.first, "mxCell/mxGeometry").attributes

    assert_equal(%w[30 40 60 30], %w[x y width height].map { |a| first[a].to_f.round.to_s })
    assert_includes REXML::XPath.first(links.first, "mxCell").attributes["style"], "fillColor=none"
    ellipse = REXML::XPath.first(links[1], "mxCell/mxGeometry").attributes

    assert_equal([130, 50, 40, 20], %w[x y width height].map { |a| ellipse[a].to_f.round })
  end

  def test_a_diagram_without_links_has_only_the_image
    doc = REXML::Document.new(Drawio.wrap_svg(%(<svg xmlns="http://www.w3.org/2000/svg" width="5" height="5"><rect width="5" height="5"/></svg>), "x"))

    assert_empty REXML::XPath.match(doc, "//UserObject")
  end

  def test_the_size_comes_from_the_attributes_the_viewbox_or_a_default
    assert_equal [10.0, 20.0], Drawio.size('<svg width="10px" height="20px">')
    assert_equal [30.0, 40.0], Drawio.size('<svg viewBox="0 0 30 40">')
    assert_equal Drawio::DEFAULT_SIZE, Drawio.size("<svg>")
  end

  def test_an_archsight_diagram_with_resolved_references_is_clickable_at_the_node_boxes
    svg = Archsight::Diagram.render(%(component "a" { label "A"; link "https://wiki.example.com/p" }\ncomponent "b" { label "B" }\na -> b\n))
    doc = REXML::Document.new(Drawio.wrap_svg(svg, "d"))
    links = REXML::XPath.match(doc, "//UserObject")

    assert_equal 1, links.length, "only the linked node, not its label or the plain node"
    assert_equal "https://wiki.example.com/p", links.first.attributes["link"]
  end

  def test_the_macro_names_the_diagram
    assert_includes Drawio.macro("pic & co"), '<ac:parameter ac:name="diagramName">pic &amp; co</ac:parameter>'
  end
end
