# frozen_string_literal: true

require_relative "../test_helper"

class DiagramTextMetricsTest < Minitest::Test
  def runs(text) = Archsight::Diagram::TextMetrics.markdown_runs(Archsight::Diagram::MarkdownText.detect(text))

  def test_returns_text_without_any_marker_character_as_one_plain_run
    assert_equal [["Control Plane@k8s", {}]], runs("Control Plane@k8s")
  end

  def test_returns_no_runs_for_empty_text
    assert_empty runs("")
  end

  def test_keeps_an_unclosed_or_lone_marker_as_plain_text
    assert_equal [["a * b", {}]], runs("a * b")
    assert_equal [["snake_case", {}]], runs("snake_case")
    assert_equal [["[not a link]", {}]], runs("[not a link]")
  end

  def test_splits_closed_markers_into_styled_runs
    assert_equal [["x ", {}], ["b", { bold: true }], [" ", {}], ["u", { underline: true }], [" ", {}], ["i", { italic: true }]],
                 runs("x **b** __u__ *i*")
    assert_equal [["see ", {}], ["docs", { link: "https://example.com" }]], runs("see [docs](https://example.com)")
  end

  def test_scans_only_text_the_lexer_flagged
    assert_equal [["**b**", {}]], Archsight::Diagram::TextMetrics.markdown_runs("**b**")
  end

  def test_flags_only_string_literals_a_marker_could_start_in
    label, plain = Archsight::Diagram::Lexer.new(%("**b**" "plain")).tokenize.first(2).map(&:value)

    assert_kind_of Archsight::Diagram::MarkdownText, label
    assert_instance_of String, plain
  end

  def test_keeps_the_flag_on_every_line_of_a_multi_line_label
    lines = Archsight::Diagram::TextMetrics.lines(Archsight::Diagram::MarkdownText.new("**a**\nb"))

    assert(lines.all?(Archsight::Diagram::MarkdownText))
  end
end
