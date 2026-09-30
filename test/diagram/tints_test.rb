# frozen_string_literal: true

require_relative "../test_helper"

class DiagramTintsTest < Minitest::Test
  def test_registers_at_least_10_named_pastel_tints
    assert_operator Archsight::Diagram::Tints.names.length, :>=, 10
  end

  def test_falls_back_to_gray_for_an_unrecognized_tint_name
    assert_same Archsight::Diagram::Tints.for("gray"), Archsight::Diagram::Tints.for("not-a-real-tint")
  end

  def test_looks_up_a_registered_tint_by_name
    green = Archsight::Diagram::Tints.for("green")

    assert_equal "green", green.name
  end
end

class DiagramTintTest < Minitest::Test
  def test_returns_its_base_fill_border_at_level_zero
    assert_equal tint.fill, tint.fill(0)
    assert_equal tint.border, tint.border(0)
  end

  def test_darkens_fill_border_monotonically_as_the_level_increases
    channel_sum = ->(hex) { [hex[1..2], hex[3..4], hex[5..6]].sum { |c| c.to_i(16) } }

    sums = (0..4).map { |level| channel_sum.call(tint.fill(level)) }

    assert_equal sums.sort.reverse, sums
    assert_operator sums.uniq.length, :>, 1
  end

  def test_clamps_darkening_at_the_max_shade_level_instead_of_approaching_black
    assert_equal tint.fill(10), tint.fill(4)
    refute_equal "#000000", tint.fill(100)
  end

  private

  def tint = @tint ||= Archsight::Diagram::Tints.for("blue")
end
