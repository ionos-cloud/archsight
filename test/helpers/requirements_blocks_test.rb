# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/helpers"

class RequirementsBlocksTest < Minitest::Test
  Blocks = Archsight::Helpers::RequirementsBlocks

  SOURCE = <<~YAML
    title: Backup requirements
    of: 'ApplicationService: name =~ "Backup"'
    priority: must
    status: [implemented, partial]
  YAML

  def html(markdown) = Kramdown::Document.new(markdown, input: "GFM").to_html

  def render(markdown)
    replaced, blocks = Blocks.extract(html(markdown))
    Blocks.restore(replaced, blocks)
  end

  def fenced(source) = "```requirements\n#{source}```\n"

  def test_parse_reads_scalars_and_lists
    spec = Blocks.parse(SOURCE)

    assert_equal "Backup requirements", spec[:title]
    assert_equal 'ApplicationService: name =~ "Backup"', spec[:of]
    assert_equal ["must"], spec[:priority]
    assert_equal %w[implemented partial], spec[:status]
  end

  def test_parse_needs_only_of
    spec = Blocks.parse("of: 'ApplicationService:'\n")

    assert_equal "", spec[:title]
    assert_empty spec[:priority]
    assert_empty spec[:status]
  end

  def test_parse_rejects_invalid_blocks
    {
      "- a\n" => "expected a mapping",
      "title: x\n" => "`of` is missing",
      "of: 'ApplicationService: ((('\n" => "invalid query",
      "of: 'ApplicationService:'\nfoo: 1\n" => "unknown key \"foo\"",
      "of: 'ApplicationService:'\npriority: urgent\n" => "priority must be must, should, may, not \"urgent\"",
      "of: 'ApplicationService:'\nstatus: [implemented, done]\n" => "status must be implemented, partial, planned, not \"done\"",
      "a: [unclosed\n" => "invalid YAML",
      "x: &a 1\nof: *a\n" => "invalid YAML"
    }.each do |source, message|
      error = assert_raises(Blocks::Error, source) { Blocks.parse(source) }

      assert_includes error.message, message, source
    end
  end

  def test_block_becomes_a_placeholder_with_the_filter_and_the_source
    out = render(fenced(SOURCE))

    assert_includes out, '<div class="requirements-embed"'
    assert_includes out, 'data-title="Backup requirements"'
    assert_includes out, 'data-of="ApplicationService: name =~ &quot;Backup&quot;"'
    assert_includes out, 'data-priority="must"'
    assert_includes out, 'data-status="implemented,partial"'
    assert_includes out, '<pre><code class="language-requirements">'
    refute_includes out, "<!--requirements-block"
  end

  def test_invalid_block_renders_an_error_box_with_the_source
    out = render(fenced("title: x\n"))

    assert_includes out, '<div class="requirements-block-error"><p><strong>Requirements error:</strong> `of` is missing'
    assert_includes out, "language-requirements"
    refute_includes out, "requirements-embed"
  end

  def test_view_blocks_are_not_requirements_blocks
    md = "```view\nkind: View\n```\n"

    assert_equal html(md), render(md)
  end

  def test_sources_finds_the_blocks_of_a_markdown_text
    markdown = "a\n\n#{fenced(SOURCE)}\n```view\nx\n```\n\n~~~requirements\nof: x\n~~~\n"

    assert_equal [SOURCE, "of: x\n"], Blocks.sources(markdown)
  end
end
