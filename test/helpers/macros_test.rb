# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/helpers"

class MacrosTest < Minitest::Test
  Macros = Archsight::Helpers::Macros

  # A macro handler for the tests: `{shout:text}` -> upper case, rejects empty text
  module Shout
    module_function

    def parse(arguments) = arguments.strip.empty? ? nil : arguments.strip
    def html(value, _context = nil) = "<b>#{value.upcase}</b>"
    def confluence(value, _context = nil) = "<u>#{value}</u>"
    def problem(arguments, _context = nil) = parse(arguments) ? nil : "needs a text"
  end

  def setup
    Macros.register("shout", Shout)
  end

  def teardown
    Macros.instance_variable_get(:@handlers).delete("shout")
  end

  def test_a_registered_macro_is_replaced_in_html
    assert_equal "<p>a <b>HI</b> b <b>YO</b></p>", Macros.render("<p>a {shout:hi} b {shout:yo}</p>")
  end

  def test_the_arguments_of_html_are_unescaped_before_they_reach_the_handler
    assert_equal "<b>A & B</b>", Macros.render("{shout:a &amp; b}")
  end

  def test_unknown_names_and_rejected_arguments_stay_as_written
    text = "{unknown:x} {shout: } {a:1} json {\"a\": 1} {Shout:x}"

    assert_equal text, Macros.render(text)
    assert_equal text, Macros.replace(text) { |_m, _v| "x" }
  end

  def test_code_is_never_touched
    html = "<p><code>{shout:a}</code> {shout:b}</p><pre><code>{shout:c}</code></pre>"

    assert_equal "<p><code>{shout:a}</code> <b>B</b></p><pre><code>{shout:c}</code></pre>", Macros.render(html)

    markdown = "{shout:a} `{shout:b}`\n\n```\n{shout:c}\n```\n"

    assert_equal "<u>a</u> `{shout:b}`\n\n```\n{shout:c}\n```\n", Macros.replace(markdown) { |m, v| m.confluence(v) }
  end

  def test_a_block_returning_nil_keeps_the_text
    assert_equal "{shout:a}", Macros.replace("{shout:a}") { |_m, _v| nil }
  end

  def test_arguments_end_at_the_closing_brace_and_cannot_hold_a_pipe_or_a_line_break
    assert_equal "{shout:a|b} {shout:a\nb}", Macros.render("{shout:a|b} {shout:a\nb}")
  end

  def test_problems_lists_registered_macros_with_bad_arguments_only
    assert_equal ["{shout: }: needs a text"], Macros.problems("{shout:ok} {shout: } {nothing:x} `{shout: }`")
  end
end
