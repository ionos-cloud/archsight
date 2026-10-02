# frozen_string_literal: true

require_relative "../../test_helper"
require "archsight/helpers"

class EmoticonMacroTest < Minitest::Test
  Macros = Archsight::Helpers::Macros

  def test_renders_the_character
    assert_equal %(<span class="macro-emoticon" role="img">\u2705</span>), Macros.render("{emoticon:2705}")
  end

  def test_a_name_becomes_label_and_title
    html = Macros.render("{emoticon:2705 check mark button}")

    assert_includes html, %(aria-label="check mark button" title="check mark button")
  end

  def test_sequences_of_code_points
    assert_includes Macros.render("{emoticon:1f468-200d-1f4bb}"), "\u{1F468}\u200D\u{1F4BB}"
  end

  def test_anything_that_is_not_an_emoji_stays_as_written
    ["zz", "41", "110000", "2705-", "", "d800"].each do |arguments|
      text = "{emoticon:#{arguments}}"

      assert_equal text, Macros.render(text), arguments
    end
  end

  def test_the_name_is_escaped
    assert_includes Macros.render("{emoticon:2705 a <b>}").sub("<span", ""), "a &lt;b&gt;"
  end

  def test_confluence_emoticon_with_and_without_a_name
    xml = ->(text) { Macros.replace(text) { |m, v| m.confluence(v) } }

    assert_equal %(<ac:emoticon ac:emoji-id="2705" ac:name="check mark button" ac:emoji-fallback="\u2705"/>), xml.call("{emoticon:2705 check mark button}")
    assert_equal %(<ac:emoticon ac:emoji-id="2705" ac:emoji-fallback="\u2705"/>), xml.call("{emoticon:2705}")
  end

  def test_classic_confluence_emoticons_by_name
    assert_equal %(<span class="macro-emoticon" role="img" aria-label="minus" title="minus">\u2796</span>), Macros.render("{emoticon:minus}")
    assert_includes Macros.render("{emoticon:thumbs-up}"), "\u{1F44D}"
    assert_equal "{emoticon:minus extra}", Macros.render("{emoticon:minus extra}")
    assert_equal "{emoticon:nonsense}", Macros.render("{emoticon:nonsense}")
  end

  def test_classic_emoticons_are_exported_as_native_name_only_emoticons
    xml = Macros.replace("{emoticon:plus}") { |m, v| m.confluence(v) }

    assert_equal %(<ac:emoticon ac:name="plus"/>), xml
  end

  def test_the_linter_message_lists_the_classic_names
    assert_includes Macros.problems("{emoticon:nonsense}").first, "minus"
  end
end
