# frozen_string_literal: true

require "test_helper"

class ConfigTest < Minitest::Test
  KLASS = Archsight::Resources::Config

  def error(key, value)
    KLASS.annotation_matching(key).validate(value).first
  end

  def test_is_a_kind_of_the_other_layer
    assert_equal "other", KLASS.layer
    assert_equal KLASS, Archsight::Resources["Config"]
  end

  def test_type_is_a_lowercase_word
    assert_nil error("config/type", "pdf")
    assert_nil error("config/type", "export-mail")
    refute_nil error("config/type", "PDF")
    refute_nil error("config/type", "two words")
  end

  def test_colours_must_be_hex
    assert_nil error("pdf/color-primary", "#0b3d91")
    assert_nil error("pdf/color-primary", "#abc")
    refute_nil error("pdf/color-primary", "blue")
    refute_nil error("pdf/color-primary", "#12345")
  end

  def test_fonts_are_plain_family_names
    assert_nil error("pdf/font-body", "Open Sans")
    refute_nil error("pdf/font-body", "\"; evil")
  end

  def test_logo_must_be_an_svg_or_png_inside_the_resources
    assert_nil error("pdf/logo", "img/logo.svg")
    refute_nil error("pdf/logo", "img/logo.gif")
    refute_nil error("pdf/logo", "../logo.svg")
  end

  def test_margin_and_header_parts
    assert_nil error("pdf/margin", "16mm")
    refute_nil error("pdf/margin", "16")
    assert_nil error("pdf/header-meta", "id, version")
    refute_nil error("pdf/header-meta", "id, shoe")
  end

  def test_heading_breaks
    assert_nil error("pdf/break-before", "1, 2")
    refute_nil error("pdf/break-before", "0")
    refute_nil error("pdf/break-before", "1,x")
    assert_nil error("pdf/keep-space", "2:30%, 3:20%")
    assert_nil error("pdf/keep-space", "2:30")
    refute_nil error("pdf/keep-space", "2:130%")
    refute_nil error("pdf/keep-space", "7:30%")
    refute_nil error("pdf/keep-space", "30%")
  end
end
