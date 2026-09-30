# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/helpers"

class DiagramBlocksTest < Minitest::Test
  DiagramBlocks = Archsight::Helpers::DiagramBlocks

  def html(markdown) = Kramdown::Document.new(markdown, input: "GFM").to_html

  def render(markdown)
    replaced, diagrams = DiagramBlocks.extract(html(markdown))
    DiagramBlocks.restore(replaced, diagrams)
  end

  def test_asd_block_becomes_inline_svg
    out = render("Before\n\n```asd\ncomponent \"a\" { label \"A\" }\n```\n")

    assert_includes out, '<figure class="asd-diagram"><svg'
    refute_includes out, "<?xml"
    refute_includes out, "language-asd"
  end

  def test_other_blocks_are_untouched
    md = "```yaml\na: 1\n```\n\n```\nplain\n```\n"

    assert_equal html(md), render(md)
  end

  def test_blocks_on_one_page_get_distinct_ids
    out = render("```asd\ncomponent \"a\" { label \"A\" }\n```\n\n```asd\ncomponent \"b\" { label \"B\" }\n```\n")
    ids = out.scan(/\bid="([^"]+)"/).flatten

    assert_equal 2, out.scan("<figure").size
    assert_equal ids.uniq, ids
  end

  def test_same_source_renders_the_same_markup
    assert_equal render("```asd\ncomponent \"a\" { label \"A\" }\n```\n"), render("```asd\ncomponent \"a\" { label \"A\" }\n```\n")
  end

  def test_invalid_block_shows_the_error_and_the_source
    out = render("```asd\nnot valid ((\n```\n")

    assert_includes out, "asd-diagram-error"
    assert_includes out, "Diagram error:"
    assert_includes out, "not valid (("
    refute_includes out, "<svg"
  end

  def test_error_message_is_escaped
    out = render("```asd\ncomponent \"<script>alert(1)</script>\" {\n```\n")

    refute_includes out, "<script>"
  end

  def test_extract_keeps_svg_out_of_the_html_until_restored
    replaced, diagrams = DiagramBlocks.extract(html("```asd\ncomponent \"a\" { label \"A\" }\n```\n"))

    refute_includes replaced, "<svg"
    assert_equal 1, diagrams.size
    assert_includes DiagramBlocks.restore(replaced, diagrams), "<svg"
  end

  def test_sources_finds_fenced_blocks
    md = "x\n\n```asd\ncomponent \"a\" { label \"A\" }\n```\n\n```yaml\nb: 1\n```\n\n~~~asd\ncomponent \"b\" { label \"B\" }\n~~~\n"

    assert_equal ["component \"a\" { label \"A\" }\n", "component \"b\" { label \"B\" }\n"], DiagramBlocks.sources(md)
  end

  def test_render_diagram_renders_a_whole_definition
    out = DiagramBlocks.render_diagram("component \"a\" { label \"A\" }\n")

    assert_includes out, '<figure class="asd-diagram"><svg'
  end

  def test_render_diagram_shows_an_escaped_error_box_for_a_broken_definition
    out = DiagramBlocks.render_diagram("<b>not valid ((\n")

    assert_includes out, "asd-diagram-error"
    assert_includes out, "&lt;b&gt;not valid (("
    refute_includes out, "<b>"
  end

  def test_resource_references_are_resolved_through_the_resolver
    resolver = ->(_) { "/kinds/ApplicationService/instances/Archsight:Web" }
    out = DiagramBlocks.render_diagram(%(component "web" { resource "Archsight:Web" }\n), resolver: resolver)

    assert_includes out, 'href="/kinds/ApplicationService/instances/Archsight:Web"'
  end

  def test_a_cached_render_is_not_reused_when_a_reference_resolves_differently
    source = %(component "web" { resource "Cache:Probe" }\n)
    found = DiagramBlocks.render_diagram(source, resolver: ->(_) { "/kinds/K/instances/Cache:Probe" })
    gone = DiagramBlocks.render_diagram(source, resolver: ->(_) { :missing })

    assert_includes found, "/kinds/K/instances/Cache:Probe"
    refute_includes gone, "/kinds/K/instances/Cache:Probe"
    assert_includes gone, "asd-broken-link"
  end

  def test_preview_returns_the_figure_and_no_error
    result = DiagramBlocks.preview("component \"a\" { label \"A\" }\n")

    assert_nil result[:error]
    assert_includes result[:html], '<figure class="asd-diagram"><svg'
  end

  def test_preview_shares_the_render_with_pages
    source = "component \"shared\" { label \"S\" }\n"

    assert_equal DiagramBlocks.render_diagram(source), DiagramBlocks.preview(source)[:html]
  end

  def test_preview_of_a_broken_definition_is_just_the_message_with_its_line
    result = DiagramBlocks.preview("component \"a\" {}\nnot valid ((\n")

    assert_nil result[:html]
    assert_match(/line 2/, result[:error])
    refute_includes result[:error], "<"
  end

  def test_preview_resolves_resource_references
    result = DiagramBlocks.preview(%(component "web" { resource "N" }\n), resolver: ->(_) { "/kinds/K/instances/N" })

    assert_includes result[:html], 'href="/kinds/K/instances/N"'
  end

  def test_extract_passes_the_resolver_to_each_block
    resolver = ->(_) { "/kinds/K/instances/N" }
    replaced, diagrams = DiagramBlocks.extract(html("```asd\ncomponent \"a\" { resource \"N\" }\n```\n"), resolver: resolver)

    assert_includes DiagramBlocks.restore(replaced, diagrams), 'href="/kinds/K/instances/N"'
  end
end
