# frozen_string_literal: true

require_relative "test_helper"
require "archsight/summary"

class SummaryLensTest < Minitest::Test
  Lens = Archsight::Summary::Lens

  def test_parse_sections
    sections = Lens.parse(<<~LENS)
      # comment
      in servedBy, realizedBy: Used by
      out dependsOn depth=2: Depends on

      out *
    LENS

    assert_equal ["Used by", "Depends on", "out *"], sections.map(&:title)
    assert_equal %w[in out out], sections.map(&:direction)
    assert_equal [%w[servedBy realizedBy], %w[dependsOn], %w[*]], sections.map(&:verbs)
    assert_equal [1, 2, 1], sections.map(&:depth)
    assert_predicate sections.last, :all_verbs?
  end

  def test_parse_errors_name_the_line
    assert_match(/line 2 .*unknown verb nope/, Lens.parse_error("out exposes\nout nope: X"))
    assert_match(/expected `out` or `in`/, Lens.parse_error("sideways exposes"))
    assert_match(/at least one verb/, Lens.parse_error("out depth=2"))
    assert_match(/depth must be 1 to 5/, Lens.parse_error("out exposes depth=9"))
    assert_match(/at least one line/, Lens.parse_error("\n# nothing\n"))
    assert_nil Lens.parse_error("in servedBy: Used by")
  end

  def test_built_in_lenses_are_valid_and_cover_every_layer
    assert_equal Archsight::Resources::LAYERS.sort, Lens::DEFAULTS.keys.sort
    Lens::DEFAULTS.each do |layer, text|
      assert_nil Lens.parse_error(text), layer
    end
  end

  def test_kind_lenses_are_valid_name_real_kinds_and_end_with_documented_in
    Lens::KIND_DEFAULTS.each do |kind, text|
      assert_nil Lens.parse_error(text), kind
      refute_nil Archsight::Resources[kind], kind
    end
    (Lens::DEFAULTS.values + Lens::KIND_DEFAULTS.values).each do |text|
      assert_match(/^in mentions, depicts: Documented in$/, text)
    end
  end

  def test_key_error_accepts_layers_and_kinds_only
    assert_nil Lens.key_error("application")
    assert_nil Lens.key_error("BusinessActor")
    assert_match(/not Nope/, Lens.key_error("Nope"))
  end

  def test_config_annotation_validates_the_lens
    annotation = Archsight::Resources::Config.annotation_matching("summary/lens-application")

    assert_empty annotation.validate("out exposes: APIs")
    assert_match(/expected `out` or `in` first/, annotation.validate("up exposes").join)
  end
end
