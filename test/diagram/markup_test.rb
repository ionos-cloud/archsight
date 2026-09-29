# frozen_string_literal: true

require_relative "../test_helper"

class DiagramMarkupTest < Minitest::Test
  def test_renders_a_self_closing_element_with_no_block
    m = Archsight::Diagram::Renderer::Markup.new
    m.element("rect", x: 1, y: 2)

    assert_equal %(<rect x="1" y="2" />\n), m.to_s
  end

  def test_nests_block_content_one_indent_level_deeper_and_dedents_after_closing
    m = Archsight::Diagram::Renderer::Markup.new
    m.element("g", class: "outer") do
      m.element("rect", x: 1)
      m.element("g", class: "inner") { m.element("path", d: "M 0 0") }
    end
    m.element("rect", x: 2) # back at depth 0

    assert_equal <<~SVG, m.to_s
      <g class="outer">
        <rect x="1" />
        <g class="inner">
          <path d="M 0 0" />
        </g>
      </g>
      <rect x="2" />
    SVG
  end

  def test_joins_an_array_class_attribute_dropping_nils_and_leaves_other_attributes_untouched
    m = Archsight::Diagram::Renderer::Markup.new
    m.element("rect", class: ["a", nil, "b", nil])

    assert_includes m.to_s, 'class="a b"'
  end

  def test_drops_a_nil_attribute_entirely_instead_of_emitting_an_empty_value
    m = Archsight::Diagram::Renderer::Markup.new
    m.element("path", d: "M 0 0", "marker-end": nil)

    refute_includes m.to_s, "marker-end"
  end

  def test_xml_escapes_attribute_values_automatically
    m = Archsight::Diagram::Renderer::Markup.new
    m.element("a", href: "https://example.com?a=1&b=2")

    assert_includes m.to_s, 'href="https://example.com?a=1&amp;b=2"'
  end

  def test_keeps_element_with_content_s_content_verbatim_unescaped_on_one_line
    m = Archsight::Diagram::Renderer::Markup.new
    m.element_with_content("text", "<tspan>already built</tspan>", x: 1)

    assert_equal %(<text x="1"><tspan>already built</tspan></text>\n), m.to_s
  end

  def test_re_indents_externally_built_raw_markup_to_the_current_depth_line_by_line
    m = Archsight::Diagram::Renderer::Markup.new
    m.element("g") { m.raw(%(<path d="a" />\n<path d="b" />\n)) }

    assert_equal <<~SVG, m.to_s
      <g>
        <path d="a" />
        <path d="b" />
      </g>
    SVG
  end

  # .tag

  def test_tag_builds_a_flat_self_closing_tag_with_no_trailing_newline
    assert_equal '<rect x="1" />', Archsight::Diagram::Renderer::Markup.tag("rect", x: 1)
  end

  def test_tag_builds_a_flat_tag_with_content
    assert_equal '<tspan class="bold">hi</tspan>', Archsight::Diagram::Renderer::Markup.tag("tspan", "hi", class: "bold")
  end
end
