# frozen_string_literal: true

require "test_helper"
require "archsight/pdf/markdown"
require_relative "pdf_fixture"

class PdfMarkdownTest < Minitest::Test
  include PdfFixture

  def setup = isolate_user_config
  def teardown = restore_user_config

  def render(source, **)
    Archsight::Pdf::Markdown.new(**).render(source)
  end

  def test_text_is_a_string_literal_never_markup
    out = render("*not* #strong[x] and $math$ <b>")

    assert_includes out, "#emph["
    assert_includes out, '#" #strong[x] and $math$ "'
  end

  def test_heading_offset
    assert_equal '#heading(level: 3)[#"Title"]', render("# Title", heading_offset: 2)
  end

  def test_heading_level_is_capped
    assert_includes render("###### Deep", heading_offset: 3), "level: 6"
  end

  def test_table_header_is_marked
    out = render("| a | b |\n|---|---|\n| 1 | 2 |\n")

    assert_includes out, "table.header([#text(weight: \"semibold\")[#\"a\"]], [#text(weight: \"semibold\")[#\"b\"]])"
    assert_includes out, "columns: 2"
  end

  def test_wiki_links_use_the_label_hook_or_the_explicit_label
    out = render("see [[Kind/Name]] and [[Kind/Name|shown]]", label: ->(target) { "Resolved #{target}" })

    assert_includes out, "Resolved Kind/Name"
    assert_includes out, "shown"
  end

  def test_embed_without_an_embed_layer_is_its_label
    assert_includes render("![[View/List]]"), '#emph[#"View/List"]'
  end

  def test_block_embeds_and_blocks_go_to_the_embeds_object
    embeds = Object.new
    def embeds.embed(reference) = "EMBED(#{reference})"
    def embeds.view_block(source) = "VIEW(#{source.strip})"
    def embeds.requirements_block(source) = "REQ(#{source.strip})"

    assert_equal "EMBED(View/List)\n\nEMBED(Analysis/X)", render("![[View/List]]\n![[Analysis/X]]", embeds: embeds)
    assert_equal "VIEW(a: 1)", render("```view\na: 1\n```", embeds: embeds)
    assert_equal "REQ(of: x)", render("```requirements\nof: x\n```", embeds: embeds)
    assert_includes render("text ![[View/List]] text", embeds: embeds), '#emph[#"View/List"]'
  end

  def test_jira_emoticon_and_unknown_macros
    assert_includes render("{jira:PROJ-1}"), '#raw("PROJ-1")'
    ENV["ARCHSIGHT_JIRA_ISSUE_URL"] = "https://jira.example.com/browse/{issue}"
    Archsight::JiraSettings.reset!

    assert_includes render("{jira:PROJ-1}"), '#link("https://jira.example.com/browse/PROJ-1")[#"PROJ-1"]'
    assert_includes render("{emoticon:2705}"), "✅"
    out = render("{nope:x} {jira:bad}")

    assert_includes out, '#"{nope:x}"'
    assert_includes out, '#"{jira:bad}"'
  end

  def test_tables_leave_rules_and_padding_to_the_layout
    out = render("| a | b |\n|---|---|\n| 1 | 2 |\n")

    refute_includes out, "stroke:"
    refute_includes out, "inset:"
    assert_includes out, "table.header("
  end

  def test_table_alignment_and_line_breaks
    out = render("| a | b |\n|:--|--:|\n| 1 | 2<br>3 |\n")

    assert_includes out, "align: (left, right,)"
    assert_includes out, "#linebreak()"
  end

  def test_mermaid_is_a_note_and_the_source
    out = render("```mermaid\ngraph TD\n```")

    assert_includes out, "Mermaid diagram"
    assert_includes out, '#raw("graph TD"'
  end

  def test_status_macro_is_a_box
    out = render("{status:green ok}")

    assert_includes out, "#box(fill: rgb(\"#d9f2e0\")"
    assert_includes out, '#"OK"'
  end

  def test_block_macros_are_dropped
    refute_includes render("{children}"), "children"
  end

  def test_task_list_shows_boxes
    out = render("- [ ] open\n- [x] done\n")

    assert_includes out, "☐"
    assert_includes out, "☑"
  end

  def test_image_hook_decides_and_a_missing_one_shows_the_alt_text
    shown = render("![alt](a.png)", image: ->(src, _alt) { "#fit-image(#{src.inspect})" })

    assert_equal '#fit-image("a.png")', shown
    assert_equal '#emph[#"alt"]', render("![alt](a.png)", image: ->(_, _) {})
  end

  def test_asd_blocks_go_to_the_diagram_hook_other_code_is_raw
    assert_equal "DIAGRAM", render("```asd\nx\n```", diagram: ->(_) { "DIAGRAM" })
    assert_includes render("```ruby\nputs 1\n```"), '#raw("puts 1", block: true, lang: "ruby")'
  end
end
