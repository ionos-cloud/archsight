# frozen_string_literal: true

require_relative "../../test_helper"
require "rexml/document"
require "archsight/helpers"

class StatusMacroTest < Minitest::Test
  Macros = Archsight::Helpers::Macros
  Status = Archsight::Helpers::Macros::Status

  def test_renders_an_image_of_the_generated_svg
    html = Macros.render("<p>State: {status:yellow WIP}</p>")

    assert_equal %(<p>State: <img class="macro-status" src="/api/v1/status/yellow/WIP.svg" alt="WIP" loading="lazy" /></p>), html
  end

  def test_colour_is_case_insensitive_and_unknown_colours_are_not_macros
    assert_includes Macros.render("{status:Green ok}"), "/api/v1/status/green/ok.svg"
    assert_equal "{status:pink ok}", Macros.render("{status:pink ok}")
    assert_equal "{status:green}", Macros.render("{status:green}")
  end

  def test_text_is_limited_and_cannot_hold_braces
    assert Status.parse("red #{"a" * 40}")
    assert_nil Status.parse("red #{"a" * 41}")
  end

  def test_url_survives_markdown_and_html_for_awkward_text
    value = Status.parse("blue a/b (c) ü?#%")
    url = Status.url(value.colour, value.text)

    refute_match(%r{[ ()?#]|/b}, url.delete_prefix("/api/v1/status/blue/"))
    assert_equal "a/b (c) ü?#%", URI.decode_www_form_component(url.delete_prefix("/api/v1/status/blue/").delete_suffix(".svg"))
  end

  def test_the_alt_text_is_escaped
    assert_includes Macros.render("{status:red <b>x</b>}").then { |h| h.sub("<img", "") }, %(alt="&lt;b&gt;x&lt;/b&gt;")
  end

  def test_the_svg_is_well_formed_upper_case_and_grows_with_the_text
    short = Status.svg("green", "ok")
    long = Status.svg("green", "a much longer status")
    REXML::Document.new(short)
    width = ->(svg) { svg[/width="(\d+)"/, 1].to_i }

    assert_includes short, ">OK</text>"
    assert_operator width.call(long), :>, width.call(short)
    assert_includes Status.svg("red", "a & <b>"), "A &amp; &lt;B&gt;"
  end

  def test_short_words_still_get_a_lozenge_of_a_minimum_width
    assert_includes Status.svg("grey", "A"), %(width="#{Status::MIN_WIDTH}")
    assert_includes Status.svg("grey", "OK"), %(width="#{Status::MIN_WIDTH}")
    assert_operator Status.svg("grey", "a much longer status")[/width="(\d+)"/, 1].to_i, :>, Status::MIN_WIDTH
  end

  def test_svg_is_cached_and_rejects_bad_input
    assert_same Status.svg("grey", "x"), Status.svg("grey", "x")
    assert_nil Status.svg("pink", "x")
    assert_nil Status.svg("grey", "")
  end

  def test_confluence_status_macro
    xml = Macros.replace("{status:yellow R&D}") { |m, v| m.confluence(v) }

    assert_equal %(<ac:structured-macro ac:name="status"><ac:parameter ac:name="colour">Yellow</ac:parameter><ac:parameter ac:name="title">R&amp;D</ac:parameter></ac:structured-macro>), xml
  end
end
