# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/mcp"

class McpHighlightsTest < Minitest::Test
  def kind_with_summary_annotations
    Class.new(Archsight::Resources::Base) do
      annotation "t/status", title: "Status", enum: %w[active archived], summary: true
      annotation "t/count", title: "Count", type: Integer, summary: true
      annotation "t/tags", title: "Tags", filter: :list, summary: true
      annotation "t/note", title: "Note"
    end
  end

  def resource(kind, annotations)
    kind.new({ "apiVersion" => "architecture/v1alpha1", "kind" => "Test",
               "metadata" => { "name" => "x", "annotations" => annotations }, "spec" => {} },
             Archsight::LineReference.new("test.yaml", 1))
  end

  def test_returns_the_summary_annotations_that_have_a_value
    kind = kind_with_summary_annotations
    result = Archsight::MCP.highlights(resource(kind, "t/status" => "active", "t/note" => "ignored"))

    assert_equal(["t/status"], result.map { |h| h[:key] })
    assert_equal "Status", result.first[:title]
    assert_equal "active", result.first[:value]
    assert_equal :tag_word, result.first[:format]
    assert_nil result.first[:type]
  end

  def test_integer_typed_values_are_numbers
    kind = kind_with_summary_annotations
    result = Archsight::MCP.highlights(resource(kind, "t/count" => "12"))

    assert_equal 12, result.first[:value]
    assert_equal "Integer", result.first[:type]
  end

  def test_list_annotations_come_back_as_arrays
    kind = kind_with_summary_annotations
    result = Archsight::MCP.highlights(resource(kind, "t/tags" => "a, b"))

    assert_equal %w[a b], result.first[:value]
  end

  def test_no_summary_annotations_or_no_values_give_an_empty_list
    kind = kind_with_summary_annotations

    assert_empty Archsight::MCP.highlights(resource(kind, {}))
    assert_empty Archsight::MCP.highlights(resource(Class.new(Archsight::Resources::Base), "x/y" => "z"))
  end
end
