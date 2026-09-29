# frozen_string_literal: true

require_relative "../test_helper"
require "rexml/document"

class DiagramElementIdsTest < Minitest::Test
  ElementIds = Archsight::Diagram::Renderer::ElementIds

  DRAWN_TAGS = %w[g rect path ellipse circle line polygon polyline text].freeze

  def test_slugs_a_source_id_down_to_a_css_safe_token_that_never_contains_a_double_underscore
    assert_equal "api-server", ElementIds.slug("api-server")
    assert_equal "api_server", ElementIds.slug("api_server")
    assert_equal "net_vpc_1", ElementIds.slug("net/vpc 1")
    assert_equal "a_b", ElementIds.slug("a__b")
    assert_equal "a", ElementIds.slug("_a.")
    assert_equal "x", ElementIds.slug("!!!")
  end

  def test_suffixes_colliding_tokens_letting_an_already_clean_id_keep_its_own
    assert_equal %w[a_b-2 a_b a_b-3], ElementIds.unique_tokens(%w[a.b a_b a/b])
    assert_equal %w[flow flow-2], ElementIds.unique_tokens(%w[flow flow])
  end

  def test_numbers_repeated_edges_between_the_same_pair_in_declaration_order
    ids = ids_for(%(component "a" { }\ncomponent "b" { }\na -> b\na -> b { label "again" }\nb -> a\n))
    edges = ids[:graph].edges.map { |e| ids[:ids].id(e) }

    assert_equal %w[asd-edge-a__b asd-edge-a__b__2 asd-edge-b__a], edges
  end

  def test_keeps_existing_ids_when_an_unrelated_object_is_declared_after_them
    before = rendered_ids(%(component "a" { }\ncomponent "b" { }\na -> b\n))
    after = rendered_ids(%(component "a" { }\ncomponent "b" { }\ncomponent "c" { }\na -> b\nb -> c\n))

    assert_empty before - after
  end

  def test_gives_every_drawn_element_a_unique_id
    doc = REXML::Document.new(Archsight::Diagram.render(everything_source))
    drawn = REXML::XPath.match(doc, "//*[not(ancestor-or-self::defs)]").select { |e| DRAWN_TAGS.include?(e.name) }
    ids = drawn.map { |e| e.attributes["id"] }

    assert_operator drawn.length, :>, 40
    assert_empty drawn.reject { |e| e.attributes["id"] }.map(&:to_s)
    assert_equal ids.length, ids.uniq.length, "duplicate ids: #{ids.tally.select { |_, n| n > 1 }.keys}"
  end

  def test_nests_a_container_s_children_inside_its_own_group
    doc = REXML::Document.new(Archsight::Diagram.render(everything_source))

    assert REXML::XPath.first(doc, "//g[@id='asd-node-edge']/g[@id='asd-node-vpc']/g[@id='asd-node-api']/rect[@id='asd-node-api__body']")
    assert REXML::XPath.first(doc, "//g[@id='asd-node-vpc']/rect[@id='asd-node-vpc__frame']")
  end

  def test_tags_each_object_s_group_and_detached_label_with_its_source_id_kind_and_line
    doc = REXML::Document.new(Archsight::Diagram.render(everything_source))

    db = element(doc, "asd-node-db_main")

    assert_equal "database", db.attributes["data-asd-kind"]
    assert_equal "db/main", db.attributes["data-asd-src"]
    assert_equal "6", db.attributes["data-asd-line"]
    assert element(doc, "asd-node-db_main__body")
    assert element(doc, "asd-node-db_main__cap")

    label = element(doc, "asd-node-db_main__label")

    assert_equal "text", label.name
    assert_equal "asd-node-db_main", label.attributes["data-asd-owner"]
    assert_equal "6", label.attributes["data-asd-line"]

    edge = element(doc, "asd-edge-api__db_main")

    assert_equal(%w[edge api db/main 15], %w[data-asd-kind data-asd-from data-asd-to data-asd-line].map { |a| edge.attributes[a] })
    assert element(doc, "asd-edge-api__db_main__line")
    assert_equal "asd-edge-api__db_main", element(doc, "asd-edge-api__db_main__label").attributes["data-asd-owner"]
  end

  def test_names_an_implements_tree_after_its_target_and_keeps_each_stub_in_its_own_edge_group
    doc = REXML::Document.new(Archsight::Diagram.render(everything_source))

    assert element(doc, "asd-tree-iface__spine")
    assert element(doc, "asd-tree-iface__trunk")
    assert REXML::XPath.first(doc, "//g[@id='asd-tree-iface']/g[@id='asd-edge-impl1__iface']/path[@id='asd-edge-impl1__iface__line']")
  end

  def test_names_a_grouped_dataflow_s_pieces_after_the_authored_dataflow
    doc = REXML::Document.new(Archsight::Diagram.render(everything_source))
    pieces = REXML::XPath.match(doc, "//g[@class='asd-dataflow']")

    assert_equal(%w[asd-dataflow-provision__prefix asd-dataflow-provision__branch0 asd-dataflow-provision__branch1],
                 pieces.map { |g| g.attributes["id"] })
    assert_equal ["provision"], pieces.map { |g| g.attributes["data-asd-src"] }.uniq
    assert_equal ["19"], pieces.map { |g| g.attributes["data-asd-line"] }.uniq
    assert element(doc, "asd-dataflow-provision__branch0__line")
    assert element(doc, "asd-dataflow-provision__branch0__halo")
    assert element(doc, "asd-legend-dataflow-provision")
  end

  private

  # Line numbers are asserted on above: `db/main` is on line 6, `api -> db/main`
  # on line 15, `dataflow "provision"` on line 19.
  def everything_source
    <<~SRC
      boundary "edge" {
        group "vpc" {
          label "VPC"
          component "api" { label "API" }
          application "app" { }
          database "db/main" { label "DB" }
        }
      }
      queue "q" { }
      actor "user" { }
      file "cfg" { }
      component "iface" { }
      component "impl1" { }
      component "impl2" { }
      api -> db/main { label "reads" }
      user -> api
      impl1 -> iface { relation "implements" }
      impl2 -> iface { relation "implements" }
      dataflow "provision" {
        hop "user"
        hop "api"
        hop group {
          hop "q"
          hop "cfg"
        }
        label "provisioning"
      }
    SRC
  end

  def ids_for(source)
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    { graph: graph, ids: ElementIds.new(graph) }
  end

  def rendered_ids(source)
    REXML::XPath.match(REXML::Document.new(Archsight::Diagram.render(source)), "//*[@id and not(ancestor::defs)]").map { |e| e.attributes["id"] }
  end

  def element(doc, id) = REXML::XPath.first(doc, "//*[@id='#{id}']")
end
