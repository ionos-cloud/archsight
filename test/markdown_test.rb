# frozen_string_literal: true

require "test_helper"
require "archsight/markdown"

class MarkdownTest < Minitest::Test
  def html(text) = Archsight::Markdown.document(text).to_html

  def test_a_single_newline_is_a_space
    assert_equal "<p>line one\nline two</p>\n", html("line one\nline two")
  end

  def test_explicit_line_breaks
    ["a  \nb", "a\\\nb", "a<br>\nb"].each do |text|
      assert_includes html(text), "a<br />\nb", text.inspect
    end
  end

  def unwrapped(text) = Archsight::Markdown.unwrapped(text).to_html

  def test_unwrapped_makes_a_soft_line_break_a_space
    assert_equal "<p>line one line two</p>\n", unwrapped("line one\nline two")
    assert_equal "<ul>\n  <li>one two</li>\n</ul>\n", unwrapped("- one\n  two")
  end

  def test_unwrapped_keeps_line_breaks_without_the_newline_after_them
    assert_equal "<p>a<br />b<br />c<br />d</p>\n", unwrapped("a  \nb\\\nc<br>\nd")
  end

  def test_unwrapped_keeps_paragraphs_and_code
    assert_equal "<p>a</p>\n\n<p>b</p>\n", unwrapped("a\n\nb")
    assert_includes unwrapped("```\nx\ny\n```"), "<code>x\ny\n</code>"
    assert_includes unwrapped("<pre>x\ny</pre>"), "<pre>x\ny</pre>"
    assert_equal "<p><code>x y</code></p>\n", unwrapped("`x\ny`")
  end

  def test_options_are_passed_on
    assert_equal "<h1>Title</h1>\n", Archsight::Markdown.document("# Title", auto_ids: false).to_html
  end
end
