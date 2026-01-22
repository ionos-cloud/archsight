# frozen_string_literal: true

require "test_helper"
require "archsight/helpers/analysis_renderer"

class AnalysisRendererTest < Minitest::Test
  include Archsight::Helpers::AnalysisRenderer

  # escape_html tests

  def test_escape_html_basic
    assert_equal "&lt;script&gt;", escape_html("<script>")
  end

  def test_escape_html_with_quotes
    assert_equal "&quot;quoted&quot;", escape_html('"quoted"')
  end

  def test_escape_html_with_ampersand
    assert_equal "&amp;test", escape_html("&test")
  end

  def test_escape_html_with_non_string
    assert_equal "123", escape_html(123)
  end

  # render_analysis_section tests - heading

  def test_render_heading_section
    section = { type: :heading, level: 1, text: "My Heading" }
    result = render_analysis_section(section)

    assert_includes result, 'class="analysis-heading level-1"'
    assert_includes result, "My Heading"
  end

  def test_render_heading_escapes_html
    section = { type: :heading, level: 2, text: "<script>alert('xss')</script>" }
    result = render_analysis_section(section)

    assert_includes result, "&lt;script&gt;"
    refute_includes result, "<script>"
  end

  # render_analysis_section tests - text

  def test_render_text_section_without_markdown
    section = { type: :text, content: "Plain text content" }
    result = render_analysis_section(section)

    assert_includes result, 'class="analysis-text"'
    assert_includes result, "Plain text content"
  end

  def test_render_text_section_with_markdown
    section = { type: :text, content: "**bold**" }
    markdown_renderer = ->(content) { "<strong>#{content.gsub("**", "")}</strong>" }
    result = render_analysis_section(section, markdown_renderer: markdown_renderer)

    assert_includes result, "<strong>bold</strong>"
  end

  def test_render_text_escapes_html_without_markdown_renderer
    section = { type: :text, content: "<b>text</b>" }
    result = render_analysis_section(section)

    assert_includes result, "&lt;b&gt;text&lt;/b&gt;"
    refute_includes result, "<b>text</b>"
  end

  # render_analysis_section tests - message

  def test_render_message_error_level
    section = { type: :message, level: :error, message: "Error occurred" }
    result = render_analysis_section(section)

    assert_includes result, 'class="analysis-message message-error"'
    assert_includes result, "iconoir-xmark-circle"
    assert_includes result, "Error occurred"
  end

  def test_render_message_warning_level
    section = { type: :message, level: :warning, message: "Warning issued" }
    result = render_analysis_section(section)

    assert_includes result, 'class="analysis-message message-warning"'
    assert_includes result, "iconoir-warning-triangle"
    assert_includes result, "Warning issued"
  end

  def test_render_message_info_level
    section = { type: :message, level: :info, message: "Info message" }
    result = render_analysis_section(section)

    assert_includes result, 'class="analysis-message message-info"'
    assert_includes result, "iconoir-info-circle"
    assert_includes result, "Info message"
  end

  def test_render_message_default_level
    section = { type: :message, level: :unknown, message: "Other message" }
    result = render_analysis_section(section)

    # Default icon should be info-circle for unknown levels
    assert_includes result, "iconoir-info-circle"
    assert_includes result, "Other message"
  end

  def test_render_message_escapes_html
    section = { type: :message, level: :error, message: "<script>xss</script>" }
    result = render_analysis_section(section)

    assert_includes result, "&lt;script&gt;xss&lt;/script&gt;"
    refute_includes result, "<script>xss</script>"
  end

  # render_analysis_section tests - table

  def test_render_table_section
    section = {
      type: :table,
      headers: %w[Name Value],
      rows: [%w[foo 1], %w[bar 2]]
    }
    result = render_analysis_section(section)

    assert_includes result, 'class="analysis-table-wrapper"'
    assert_includes result, "<thead>"
    assert_includes result, "<th>Name</th>"
    assert_includes result, "<th>Value</th>"
    assert_includes result, "<tbody>"
    assert_includes result, "<td>foo</td>"
    assert_includes result, "<td>1</td>"
    assert_includes result, "<td>bar</td>"
    assert_includes result, "<td>2</td>"
  end

  def test_render_table_escapes_html
    section = {
      type: :table,
      headers: ["<b>Header</b>"],
      rows: [["<script>xss</script>"]]
    }
    result = render_analysis_section(section)

    assert_includes result, "&lt;b&gt;Header&lt;/b&gt;"
    assert_includes result, "&lt;script&gt;xss&lt;/script&gt;"
  end

  def test_render_table_handles_non_string_cells
    section = {
      type: :table,
      headers: %w[Number],
      rows: [[123], [nil]]
    }
    result = render_analysis_section(section)

    assert_includes result, "<td>123</td>"
    assert_includes result, "<td></td>"
  end

  # render_analysis_section tests - list

  def test_render_list_section
    section = { type: :list, items: %w[apple banana cherry] }
    result = render_analysis_section(section)

    assert_includes result, 'class="analysis-list"'
    assert_includes result, "<li>apple</li>"
    assert_includes result, "<li>banana</li>"
    assert_includes result, "<li>cherry</li>"
  end

  def test_render_list_escapes_html
    section = { type: :list, items: ["<script>xss</script>"] }
    result = render_analysis_section(section)

    assert_includes result, "&lt;script&gt;xss&lt;/script&gt;"
    refute_includes result, "<script>xss</script>"
  end

  # render_analysis_section tests - code

  def test_render_code_section_with_language
    section = { type: :code, lang: "ruby", content: "puts 'hello'" }
    result = render_analysis_section(section)

    assert_includes result, 'class="code"'
    assert_includes result, 'class="language-ruby"'
    # HTML entity encoding for single quotes (&#39; or &#x27;)
    assert_match(/puts.*hello/, result)
  end

  def test_render_code_section_without_language
    section = { type: :code, lang: nil, content: "plain code" }
    result = render_analysis_section(section)

    assert_includes result, 'class="code"'
    assert_includes result, "<code>"
    refute_includes result, "language-"
    assert_includes result, "plain code"
  end

  def test_render_code_escapes_html
    section = { type: :code, content: "<script>alert('xss')</script>" }
    result = render_analysis_section(section)

    assert_includes result, "&lt;script&gt;"
    refute_includes result, "<script>alert"
  end

  # render_analysis_section tests - unknown type

  def test_render_unknown_section_type
    section = { type: :unknown, content: "test" }
    result = render_analysis_section(section)

    assert_equal "", result
  end

  def test_render_nil_type
    section = { type: nil, content: "test" }
    result = render_analysis_section(section)

    assert_equal "", result
  end

  # render_analysis_table tests

  def test_render_analysis_table_public_method
    section = {
      type: :table,
      headers: %w[Col1 Col2],
      rows: [%w[a b]]
    }
    result = render_analysis_table(section)

    assert_includes result, "<th>Col1</th>"
    assert_includes result, "<th>Col2</th>"
    assert_includes result, "<td>a</td>"
    assert_includes result, "<td>b</td>"
  end

  def test_render_analysis_table_empty_rows
    section = {
      type: :table,
      headers: %w[Header],
      rows: []
    }
    result = render_analysis_table(section)

    assert_includes result, "<th>Header</th>"
    assert_includes result, "<tbody></tbody>"
  end
end
