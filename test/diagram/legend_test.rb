# frozen_string_literal: true

require_relative "../test_helper"
require "rexml/document"

class DiagramLegendTest < Minitest::Test
  Legend = Archsight::Diagram::Legend

  # Four leaves side by side, each a different shape -- a legend worth
  # drawing, next to a diagram much wider than it is tall.
  WIDE = <<~SRC
    layer {
      component "a" { }
      database "b" { }
      api "c" { }
      queue "d" { }
    }
    a -> b
  SRC

  # The same four leaves on top of each other: taller than wide.
  TALL = WIDE.sub("layer {", "stack {")

  def test_puts_the_legend_below_a_wide_diagram_and_beside_a_tall_one_by_default
    wide = layout(WIDE)
    tall = layout(TALL)

    assert_equal "bottom", wide.legend.side
    assert_in_delta main(wide)[:bottom] + Legend::GAP, frame(wide).top, 1e-9
    assert_in_delta main(wide)[:left], frame(wide).left, 1e-9 # aligned to the start, not stretched

    assert_equal "right", tall.legend.side
    assert_in_delta main(tall)[:right] + Legend::GAP, frame(tall).left, 1e-9
    assert_in_delta main(tall)[:top], frame(tall).top, 1e-9
  end

  def test_puts_the_legend_wherever_the_source_or_the_caller_says
    { "left" => ->(m, f) { f.right + Legend::GAP - m[:left] },
      "top" => ->(m, f) { f.bottom + Legend::GAP - m[:top] },
      "right" => ->(m, f) { m[:right] + Legend::GAP - f.left },
      "bottom" => ->(m, f) { m[:bottom] + Legend::GAP - f.top } }.each do |side, gap_error|
      from_source = layout(%(legend "#{side}"\n#{WIDE}))
      from_caller = layout(%(legend "top"\n#{WIDE}), legend: side)

      [from_source, from_caller].each do |l|
        assert_equal side, l.legend.side
        assert_in_delta 0.0, gap_error.call(main(l), frame(l)), 1e-9, side
      end
    end
  end

  def test_leaves_the_legend_out_entirely_for_none
    none = layout(%(legend "none"\n#{WIDE}))

    assert_nil none.legend
    assert_empty(none.boxes.keys.grep(/\A#{Legend::ID_PREFIX}/o))
    refute_includes Archsight::Diagram.render(WIDE, legend: "none"), %(id="asd-legend")
  end

  def test_never_moves_the_diagram_itself_only_places_the_legend_beside_it
    %w[auto bottom right left top].each do |mode|
      with = layout(WIDE, legend: mode)
      without = layout(WIDE, legend: "none")
      shift = %w[x y].map { |a| with.boxes["a"].send(a) - without.boxes["a"].send(a) }

      %w[a b c d].each do |id|
        assert_in_delta without.boxes[id].x + shift[0], with.boxes[id].x, 1e-9, "#{mode}: #{id}"
        assert_in_delta without.boxes[id].y + shift[1], with.boxes[id].y, 1e-9, "#{mode}: #{id}"
      end
    end
  end

  def test_fits_as_many_columns_below_the_diagram_as_its_width_allows_each_as_wide_as_its_own_entries
    l = layout(WIDE, legend: "bottom")
    columns = l.legend.frame.children.first.children

    assert_operator columns.length, :>, 1
    assert_operator frame(l).width, :<=, main(l)[:width]
    columns.each do |column|
      widths = column.children.map { |e| l.boxes[e.id].width }

      assert_equal [column.children.map { |e| e.layout_size.first }.max], widths.uniq
    end
  end

  def test_uses_as_few_columns_beside_the_diagram_as_its_height_allows
    l = layout(TALL, legend: "right")

    assert_equal 1, l.legend.frame.children.first.children.length
    assert_operator frame(l).height, :<=, main(l)[:height]
  end

  def test_parses_the_legend_setting_and_rejects_bad_or_repeated_ones
    parse = ->(src) { Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(src)) }

    assert_equal "right", parse.call(%(legend "right"\ncomponent "a" { }\n)).legend_mode
    assert_nil parse.call(%(component "a" { }\n)).legend_mode
    # A node may still be called "legend": an edge follows its id with an
    # arrow, not a string.
    assert_equal 1, parse.call(%(component "legend" { }\ncomponent "b" { }\nlegend -> b\n)).edges.length

    unknown = assert_raises(Archsight::Diagram::GraphError) { parse.call(%(legend "middle"\n)) }

    assert_equal 'unknown legend "middle" (line 1); expected one of auto, bottom, right, left, top, none', unknown.message
    twice = assert_raises(Archsight::Diagram::GraphError) { parse.call(%(legend "top"\nlegend "right"\n)) }

    assert_equal "legend already set at line 1 (line 2)", twice.message
  end

  def test_keeps_every_line_out_of_the_legend
    source = File.read(File.expand_path("fixtures/dp_cp_view.asd", __dir__))
    doc = REXML::Document.new(Archsight::Diagram.render(source, relation_filter: Archsight::Diagram::Relations.names))
    bg = REXML::XPath.first(doc, "//rect[@id='asd-legend__bg']")
    x, y, w, h = %w[x y width height].map { |a| bg.attributes[a].to_f }
    rect = Archsight::Diagram::Renderer::LabelPlacer::Rect.new(x, x + w, y, y + h)

    crossing = REXML::XPath.match(doc, "//path[contains(@id,'__line')]").select do |path|
      path.attributes["d"].scan(/-?[\d.]+/).map(&:to_f).each_slice(2).each_cons(2).any? do |(x1, y1), (x2, y2)|
        Archsight::Diagram::EdgeRouter::PathMetrics.segment_crosses_box?(x1, y1, x2, y2, rect)
      end
    end

    assert_empty(crossing.map { |p| p.attributes["id"] })
  end

  private

  def layout(source, legend: nil)
    graph = Archsight::Diagram::Graph.build(Archsight::Diagram::Parser.parse(source))
    Archsight::Diagram::Layout.compute(graph, legend: legend)
  end

  def frame(layout) = layout.boxes[layout.legend.frame.id]

  # The extent of every box but the legend's.
  def main(layout)
    boxes = layout.boxes.reject { |id, _| id.start_with?(Legend::ID_PREFIX) }.values
    left = boxes.map(&:left).min
    right = boxes.map(&:right).max
    top = boxes.map(&:top).min
    bottom = boxes.map(&:bottom).max
    { left: left, right: right, top: top, bottom: bottom, width: right - left, height: bottom - top }
  end
end
