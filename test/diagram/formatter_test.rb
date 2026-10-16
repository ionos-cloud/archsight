# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/diagram"
require "archsight/diagram/formatter"

class DiagramFormatterTest < Minitest::Test
  def formatted(source) = Archsight::Diagram::Formatter.format(source)

  def test_indents_by_brace_depth_and_dedents_closing_braces
    source = <<~ASD
      layer "l" {
      stack {
            component "a" { label "A" }
        }
          }
    ASD

    assert_equal <<~ASD, formatted(source)
      layer "l" {
        stack {
          component "a" { label "A" }
        }
      }
    ASD
  end

  def test_keeps_comments_one_line_blocks_and_single_blank_lines
    source = %(# a diagram\n\n\n\nlayer {\n    # the parts\n  component "a" { label "x"; tint "teal" }   \n\n\n  a -- b\n  component "b" { }\n}\n\n\n)

    assert_equal %(# a diagram\n\nlayer {\n  # the parts\n  component "a" { label "x"; tint "teal" }\n\n  a -- b\n  component "b" { }\n}\n), formatted(source)
  end

  def test_ignores_braces_in_strings_and_comments
    source = %(layer {\n# not a block {\ncomponent "a" { label "{x}" }\n}\n)

    assert_equal %(layer {\n  # not a block {\n  component "a" { label "{x}" }\n}\n), formatted(source)
  end

  def test_indents_a_multi_line_string_one_level_deeper_and_keeps_its_blank_lines
    source = %(component "a" {\nlabel "first\n\n          second"\n}\n)
    result = formatted(source)

    assert_equal %(component "a" {\n  label "first\n\n    second"\n}\n), result
    assert_equal Archsight::Diagram::Parser.parse(source).first.attrs, Archsight::Diagram::Parser.parse(result).first.attrs
  end

  def test_formatting_twice_changes_nothing
    source = File.read(File.expand_path("../../examples/diagrams/aws_vpc.asd", __dir__)).gsub(/^ +/, "")
    once = formatted(source)

    refute_equal source, once
    assert_equal once, formatted(once)
  end

  def test_the_examples_are_formatted
    Dir[File.expand_path("../../examples/**/*.asd", __dir__)].each do |path|
      source = File.read(path)

      assert_equal source, formatted(source), "#{path} is not formatted"
    end
  end

  def test_an_invalid_diagram_is_an_error
    assert_raises(Archsight::Diagram::Error) { formatted(%(layer {\n  component "a" {\n}\n)) }
  end
end
