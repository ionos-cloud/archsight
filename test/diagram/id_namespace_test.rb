# frozen_string_literal: true

require_relative "../test_helper"
require "rexml/document"

class DiagramIdNamespaceTest < Minitest::Test
  SOURCE = <<~SRC
    layer "app" {
      component "web" { label "Web" }
      component "api" { label "API" }
    }
    boundary "dc" { component "db" { label "DB" } }
    web -> api { label "calls" }
    api -> db { relation "data" }
    dataflow "sync" {
      hop "web"
      hop "api"
      color "#1a56db"
    }
  SRC

  def test_nil_prefix_leaves_the_output_untouched
    assert_equal Archsight::Diagram.render(SOURCE), Archsight::Diagram.render(SOURCE, id_prefix: nil)
    assert_includes Archsight::Diagram.render(SOURCE), 'id="asd-node-web"'
  end

  def test_every_id_is_prefixed
    svg = Archsight::Diagram.render(SOURCE, id_prefix: "d1")
    ids = svg.scan(/\bid="([^"]+)"/).flatten

    refute_empty ids
    assert_empty(ids.reject { |id| id.start_with?("d1-") })
    assert_empty svg.scan(/#(?:asd|arrow)-[\w-]*/)
    assert_includes ids, "d1-asd-node-web"
  end

  def test_references_still_resolve
    svg = Archsight::Diagram.render(SOURCE, id_prefix: "d1")
    ids = svg.scan(/\bid="([^"]+)"/).flatten

    refs = svg.scan(/url\(#([^)]+)\)/).flatten.uniq

    refute_empty refs
    assert_empty refs - ids
    assert_empty svg.scan(/data-asd-owner="([^"]+)"/).flatten.uniq - ids
    REXML::Document.new(svg) # still well formed
  end

  def test_two_diagrams_with_the_same_nodes_share_no_ids
    a = Archsight::Diagram.render(SOURCE, id_prefix: "a").scan(/\bid="([^"]+)"/).flatten
    b = Archsight::Diagram.render(SOURCE, id_prefix: "b").scan(/\bid="([^"]+)"/).flatten

    assert_empty a & b
  end

  def test_hover_rules_follow_the_prefixed_ids
    style = Archsight::Diagram.render(SOURCE, id_prefix: "d1")[%r{<style>(?:(?!</style>).)*:hover(?:(?!</style>).)*</style>}m]

    assert_includes style, "#d1-asd-node-web"
    refute_match(/#asd-/, style)
  end

  def test_label_text_is_never_rewritten
    svg = Archsight::Diagram.render(%(component "x" { label "see #asd-node-x" }), id_prefix: "d1")

    assert_includes svg, "see #asd-node-x"
  end

  def test_rejects_an_unsafe_prefix
    assert_raises(ArgumentError) { Archsight::Diagram.render(SOURCE, id_prefix: %(a"b)) }
  end
end
