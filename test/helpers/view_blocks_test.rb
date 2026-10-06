# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/helpers"

class ViewBlocksTest < Minitest::Test
  ViewBlocks = Archsight::Helpers::ViewBlocks

  VIEW = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: View
    metadata:
      name: Services without backup
      annotations:
        view/query: 'ApplicationService: backup/mode == "none"'
        view/fields: name, @owner , @status
        view/sort: -name
        view/type: list:name
  YAML

  def html(markdown) = Kramdown::Document.new(markdown, input: "GFM").to_html

  def render(markdown)
    replaced, blocks = ViewBlocks.extract(html(markdown))
    ViewBlocks.restore(replaced, blocks)
  end

  def fenced(source) = "```view\n#{source}```\n"

  def test_parse_reads_the_view_resource
    spec = ViewBlocks.parse(VIEW)

    assert_equal "Services without backup", spec[:title]
    assert_equal 'ApplicationService: backup/mode == "none"', spec[:query]
    assert_equal ["name", "@owner", "@status"], spec[:fields]
    assert_equal ["-name"], spec[:sort]
    assert_equal "list:name", spec[:type]
  end

  def test_parse_defaults_and_optional_parts
    spec = ViewBlocks.parse("metadata:\n  annotations:\n    view/query: 'ApplicationService:'\n")

    assert_equal "", spec[:title]
    assert_empty spec[:fields]
    assert_empty spec[:sort]
    assert_equal "list:name+kind", spec[:type]
  end

  def test_parse_ignores_other_annotations_but_not_unknown_view_keys
    other = "kind: View\nmetadata:\n  annotations:\n    view/query: 'ApplicationService:'\n    architecture/description: x\n"

    assert_equal "ApplicationService:", ViewBlocks.parse(other)[:query]

    typo = "metadata:\n  annotations:\n    view/query: 'ApplicationService:'\n    view/feilds: name\n"
    error = assert_raises(ViewBlocks::Error) { ViewBlocks.parse(typo) }

    assert_includes error.message, "view/feilds"
  end

  def test_parse_rejects_invalid_blocks
    {
      "- a\n- b\n" => "expected a View resource",
      "just text\n" => "expected a View resource",
      "kind: Page\nmetadata: {}\n" => "kind must be View",
      "kind: View\nmetadata:\n  name: x\n" => "view/query is missing",
      "metadata:\n  annotations:\n    view/query: 'ApplicationService: ((('\n" => "invalid query",
      "metadata:\n  annotations:\n    view/query: 'ApplicationService:'\n    view/type: table\n" => "view/type must be one of",
      "a: [unclosed\n" => "invalid YAML",
      "metadata:\n  annotations: nope\n" => "metadata.annotations must be a mapping",
      "x: &a 1\ny: *a\n" => "invalid YAML"
    }.each do |source, message|
      error = assert_raises(ViewBlocks::Error, source) { ViewBlocks.parse(source) }

      assert_includes error.message, message, source
    end
  end

  def test_view_block_becomes_a_placeholder_with_the_spec_and_the_source
    out = render(fenced(VIEW))

    assert_includes out, '<div class="view-embed"'
    assert_includes out, 'data-title="Services without backup"'
    assert_includes out, 'data-query="ApplicationService: backup/mode == &quot;none&quot;"'
    assert_includes out, 'data-fields="name,@owner,@status"'
    assert_includes out, 'data-sort="-name"'
    assert_includes out, 'data-type="list:name"'
    assert_includes out, '<pre><code class="language-view">'
    refute_includes out, "<!--view-block"
  end

  def test_invalid_block_renders_an_error_box_with_the_source
    out = render(fenced("kind: View\nmetadata:\n  name: x\n"))

    assert_includes out, '<div class="view-block-error"><p><strong>View error:</strong> view/query is missing</p>'
    assert_includes out, "language-view"
    refute_includes out, "view-embed"
  end

  def test_other_blocks_are_untouched
    md = "```yaml\na: 1\n```\n\n```\nplain\n```\n"

    assert_equal html(md), render(md)
  end

  def test_several_blocks_and_nesting
    out = render("- item\n\n  #{fenced(VIEW).gsub("\n", "\n  ")}\n\n> quote\n\n#{fenced(VIEW)}")

    assert_equal 2, out.scan('class="view-embed"').size
  end

  def test_sources_finds_the_blocks_of_a_markdown_text
    markdown = "a\n\n#{fenced(VIEW)}\n```asd\nx\n```\n\n~~~view\nkind: View\n~~~\n"

    assert_equal [VIEW, "kind: View\n"], ViewBlocks.sources(markdown)
  end
end
