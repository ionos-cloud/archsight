# frozen_string_literal: true

require_relative "pdf_fixture"
require "archsight/pdf/dependency_graph"

class PdfDependencyGraphTest < Minitest::Test
  include PdfFixture

  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Core:Billing
      annotations:
        architecture/description: Bills the customers.
    spec:
      dependsOn:
        applicationComponents:
          - Core:Shipping
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Core:Shipping
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Core:Lonely
    spec: {}
  YAML

  DependencyGraph = Archsight::Pdf::DependencyGraph

  def setup
    build_resources
    File.write(File.join(@dir, "graph.yaml"), RESOURCES)
    @db.reload!
    @saved_dot = ENV.fetch("ARCHSIGHT_PDF_DOT", nil)
  end

  def teardown
    @saved_dot ? ENV["ARCHSIGHT_PDF_DOT"] = @saved_dot : ENV.delete("ARCHSIGHT_PDF_DOT")
    cleanup_resources
  end

  def dot?
    system("dot", "-V", out: File::NULL, err: File::NULL)
  end

  def graph(name, **)
    DependencyGraph.new(@db, @db.instance_by_kind("ApplicationComponent", name), **)
  end

  def graph_pictures(name)
    document(name).files.keys.grep(/\.pdf\z/)
  end

  def document(name)
    Archsight::Pdf::Document.new(@db, @db.instance_by_kind("ApplicationComponent", name), resources_dir: @dir)
  end

  def test_paint_colours_the_nodes_by_layer_and_removes_the_label_table_borders
    dot = [
      %( "A" [ "class" = "ApplicationComponent layer-application" "label" = <<TABLE><TR><TD>x</TD></TR></TABLE>> ];),
      %( "B" [ "class" = "BusinessActor layer-business" ];)
    ].join("\n")
    out = DependencyGraph.paint(dot)

    assert_includes out, '"fillcolor" = "#6CBEED" "color" = "#6CBEED"'
    assert_includes out, '"fillcolor" = "#F9DC5C" "color" = "#F9DC5C"'
    assert_includes out, '<TABLE BORDER="0" CELLBORDER="0" CELLSPACING="0">'
  end

  def test_colour_layers_puts_the_style_after_the_svg_tag
    out = DependencyGraph.colour_layers(%(<?xml version="1.0"?>\n<svg width="1" height="1">\n<g/></svg>))

    assert_match(/<svg width="1" height="1">\n<style>/, out)
    assert_includes out, ".layer-technology path[fill=\"lightgrey\"]"
  end

  def test_a_resource_without_relations_has_no_graph
    refute_predicate graph("Core:Lonely"), :relations?
    assert_nil graph("Core:Lonely").pdf
    assert_nil graph("Core:Lonely").svg
  end

  def test_without_dot_there_is_no_graph_and_no_error
    assert_predicate graph("Core:Billing"), :relations?
    assert_nil graph("Core:Billing", binary: "/nonexistent/dot").pdf
    assert_nil graph("Core:Billing", binary: "/nonexistent/dot").svg
  end

  def test_the_direction_is_the_one_that_fits_the_page_better
    skip "graphviz is not installed" unless dot?

    wide = graph("Core:Billing")
    dot = DependencyGraph.paint(wide.send(:create_graph_one, @db, "ApplicationComponent", "Core:Billing", max_depth: 2, layers: nil))

    assert_includes %w[LR TB], wide.send(:oriented, dot)[/"rankdir" = "(\w+)"/, 1]
    assert_includes wide.send(:with_direction, dot, "TB"), '"rankdir" = "TB"'
    assert_equal 0, graph("Core:Billing", binary: "/nonexistent/dot").send(:fit, dot)
  end

  def test_dot_draws_a_pdf_and_an_svg
    skip "graphviz is not installed" unless dot?

    assert graph("Core:Billing").pdf.start_with?("%PDF")
    assert_includes graph("Core:Billing").svg, "<style>"
  end

  def test_the_resource_document_has_the_graph_picture_before_the_properties_and_without_a_heading
    skip "graphviz is not installed" unless dot?

    main = document("Core:Billing").files["main.typ"]

    assert_equal 1, graph_pictures("Core:Billing").size
    assert_includes main, "#fit-image(\"img-1.pdf\", max-height: 0.8)"
    refute_includes main, "Dependency graph"
    assert_operator main.index("#fit-image"), :<, main.index('#"Properties"')
    assert_empty graph_pictures("Core:Lonely")
  end

  def test_the_graph_comes_before_the_description_and_the_facts
    skip "graphviz is not installed" unless dot?

    main = document("Core:Billing").files["main.typ"]

    assert_operator main.index("#fit-image"), :<, main.index("Bills the customers.")
    assert_operator main.index("Bills the customers."), :<, main.index('#"Properties"')
  end

  def test_the_tag_leaves_the_graph_out
    skip "graphviz is not installed" unless dot?

    File.write(File.join(@dir, "graph.yaml"), RESOURCES.sub("    architecture/description: Bills the customers.\n", "    architecture/description: Bills the customers.\n    architecture/tags: pdf:no-graph\n"))
    @db.reload!

    assert_empty graph_pictures("Core:Billing")
  end

  def test_a_missing_dot_leaves_the_document_without_a_graph
    ENV["ARCHSIGHT_PDF_DOT"] = "/nonexistent/dot"

    assert_empty graph_pictures("Core:Billing")
  end

  def test_the_document_with_a_graph_compiles
    skip "typst or graphviz is not installed" unless typst? && dot?

    assert Archsight::Pdf.compile(Archsight::Pdf.document(@db, @db.instance_by_kind("ApplicationComponent", "Core:Billing"), resources_dir: @dir)).start_with?("%PDF")
  end
end
