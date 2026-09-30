# frozen_string_literal: true

require_relative "../test_helper"
require "rexml/document"

class DiagramResourceLinksTest < Minitest::Test
  SOURCE = <<~SRC
    group "g" { resource "ApplicationService/Archsight:Web"
      component "web" { resource "Archsight:Web" }
      component "gone" { resource "Nope" }
      component "dup" { resource "Dup" }
      component "plain" { label "Plain" }
    }
  SRC

  RESOLVER = lambda do |reference|
    { "Archsight:Web" => "/kinds/ApplicationService/instances/Archsight:Web",
      "ApplicationService/Archsight:Web" => "/kinds/ApplicationService/instances/Archsight:Web",
      "Nope" => :missing, "Dup" => :ambiguous }.fetch(reference)
  end

  def render(**) = Archsight::Diagram.render(SOURCE, **)

  def test_a_resolved_reference_becomes_a_link_on_the_node_and_its_label
    svg = render(resolver: RESOLVER)

    assert_equal 4, svg.scan('<a href="/kinds/ApplicationService/instances/Archsight:Web" class="asd-link">').length # shape + label, node and group
  end

  def test_an_unresolved_reference_marks_the_node_broken_with_a_tooltip_instead_of_failing
    svg = render(resolver: RESOLVER)
    doc = REXML::Document.new(svg)
    broken = doc.root.get_elements("//g[@class='asd-broken-link']")

    assert_equal(%w[asd-node-gone asd-node-dup], broken.map { |g| g.attributes["id"] })
    assert_equal(["Resource Nope not found", "Resource Dup is ambiguous, use Kind/Name"], broken.map { |g| g.elements["title"].text })
    refute_includes broken.first.to_s, "<a "
  end

  def test_unresolved_collects_what_could_not_be_resolved
    unresolved = []
    render(resolver: RESOLVER, unresolved: unresolved)

    assert_equal [{ node: "gone", reference: "Nope", reason: "not found", line: 3 },
                  { node: "dup", reference: "Dup", reason: "is ambiguous, use Kind/Name", line: 4 }], unresolved
  end

  def test_without_a_resolver_a_resource_attribute_is_inert
    svg = render

    refute_includes svg, "<a "
    refute_includes svg, 'class="asd-broken-link"'
  end

  def test_a_diagram_without_resources_renders_the_same_with_or_without_a_resolver
    source = %(component "a" { label "A" }\ncomponent "b" { link "https://example.com" }\na -> b\n)

    assert_equal Archsight::Diagram.render(source), Archsight::Diagram.render(source, resolver: RESOLVER)
  end

  def test_a_resolver_returning_something_unexpected_is_an_error
    assert_raises(ArgumentError) { Archsight::Diagram.render(SOURCE, resolver: ->(_) { :oops }) }
  end

  def test_resource_and_link_cannot_be_combined_and_the_format_is_checked
    assert_raises(Archsight::Diagram::GraphError) { Archsight::Diagram.render(%(component "a" { link "/x"; resource "Y" })) }
    assert_raises(Archsight::Diagram::GraphError) { Archsight::Diagram.render(%(component "a" { resource "a b" })) }
    assert_raises(Archsight::Diagram::GraphError) { Archsight::Diagram.render(%(component "a" { resource "A/B/C" })) }
  end
end
