# frozen_string_literal: true

require "test_helper"
require "archsight/analysis"
require "open3"
require "tmpdir"

class TypstRendererTest < Minitest::Test
  Analysis = Struct.new(:name)

  NASTY = %(#set page(width: 1pt) $x$ *b* _i_ `c` <l> @r [x] "q" \\ // end)

  def result(name = "Analysis:Demo", sections: [], success: true, error: nil, backtrace: nil)
    Archsight::Analysis::Result.new(Analysis.new(name), success: success, error: error,
                                                        error_backtrace: backtrace, sections: sections, duration: 0.5)
  end

  def render(results, verbose: false, template: nil)
    Archsight::Analysis::TypstRenderer.new(Array(results), verbose: verbose, template: template).render
  end

  def test_data_sections_are_not_rendered_without_template
    typst = render(result(sections: [{ type: :data, key: "vsa", value: { "secret" => 1 } }]))

    refute_includes typst, "secret"
  end

  def test_template_imports_file_and_wraps_each_result
    data = { "functions" => [{ "id" => "SF01", "desc" => %(a "q" \\ b\nc) }], "empty" => {}, "one" => [1],
             "flags" => [true, false, nil, 1.5, :sym] }
    sections = [{ type: :data, key: "vsa", value: data }, { type: :heading, text: "Body", level: 0 }]
    typst = render([result(sections: sections), result("Analysis:Bad", success: false, error: "boom")],
                   template: "../tpl/vsa.typ")

    assert_includes typst, '#import "../tpl/vsa.typ": *'
    assert_includes typst, "#show: archsight-report.with(count: 2, passed: 1, failed: 1, findings: 1)"
    refute_includes typst, "#set page("
    assert_includes typst, '#analysis-result(name: "Analysis:Demo", description: none, state: "findings", duration: "0.50s", '
    assert_includes typst, 'data: ("vsa": ("functions": (("id": "SF01", "desc": "a \\"q\\" \\\\ b\\nc"),), ' \
                           '"empty": (:), "one": (1,), "flags": (true, false, none, 1.5, "sym"))))[' \
                           "\n#heading(level: 2)[#\"Body\"]\n]"
    assert_includes typst, '#analysis-result(name: "Analysis:Bad", description: none, state: "failed"'
    assert_includes typst, "data: (:))[\n#block(fill:"
  end

  def test_template_shows_every_row
    rows = Array.new(12) { |i| ["row#{i}"] }

    assert_includes render(result(sections: [{ type: :table, headers: ["N"], rows: rows }]), template: "t.typ"), "row11"
  end

  def test_document_has_preamble_title_and_summary
    typst = render([result, result("Analysis:Bad", success: false, error: "boom")])

    assert_includes typst, "#set page("
    assert_includes typst, '#"Archsight analysis"'
    assert_includes typst, '#"1 passed"'
    assert_includes typst, '#"1 failed"'
    assert_includes typst, '#heading(level: 1)[#"Analysis:Demo"]'
  end

  def test_headings_are_shifted_below_the_analysis_name
    typst = render(result(sections: [{ type: :heading, text: "Top", level: 0 }, { type: :heading, text: "Deep", level: 9 }]))

    assert_includes typst, '#heading(level: 2)[#"Top"]'
    assert_includes typst, '#heading(level: 6)[#"Deep"]'
  end

  def test_table_cells_are_string_literals
    typst = render(result(sections: [{ type: :table, headers: %w[A B], rows: [[NASTY, 2], ["only one"]] }]))

    assert_includes typst, "#table(columns: 2"
    assert_includes typst, "[#strong[#\"A\"]]"
    assert_includes typst, %([#"#{NASTY.gsub("\\") { "\\\\" }.gsub('"') { '\\"' }}"])
    assert_includes typst, '[#""]' # short row is padded
  end

  def test_tables_and_lists_are_cut_unless_verbose
    rows = Array.new(12) { |i| ["row#{i}"] }
    sections = [{ type: :table, headers: ["N"], rows: rows }, { type: :list, items: rows.flatten }]

    typst = render(result(sections: sections))

    refute_includes typst, "row11"
    assert_includes typst, "...and 2 more rows"
    assert_includes typst, "...and 2 more items"
    assert_includes render(result(sections: sections), verbose: true), "row11"
  end

  def test_markdown_text_and_list_items
    typst = render(result(sections: [
                            { type: :text, content: "Hello **bold** and _it_ with `code` and [a link](https://example.com)" },
                            { type: :list, items: ["**k:** v"] }
                          ]))

    assert_includes typst, '#strong[#"bold"]'
    assert_includes typst, '#emph[#"it"]'
    assert_includes typst, '#raw("code")'
    assert_includes typst, '#link("https://example.com")[#"a link"]'
    assert_includes typst, '#list([#strong[#"k:"]#" v"])'
  end

  def test_messages_are_coloured_blocks
    typst = render(result(sections: [{ type: :message, level: :warning, message: "careful" }]))

    assert_includes typst, "#block(fill: rgb(\"#fff3cc\")"
    assert_includes typst, '#"careful"'
  end

  def test_failure_shows_error_and_backtrace_when_verbose
    failed = result(success: false, error: "boom", backtrace: ["a.rb:1"])

    assert_includes render(failed), "boom"
    refute_includes render(failed), "a.rb:1"
    assert_includes render(failed, verbose: true), '#raw("a.rb:1", block: true)'
  end

  def test_code_block_keeps_language_only_when_safe
    typst = render(result(sections: [{ type: :code, content: "x = 1", lang: "ruby" },
                                     { type: :code, content: "y", lang: %(a"b) }]))

    assert_includes typst, '#raw("x = 1", block: true, lang: "ruby")'
    assert_includes typst, '#raw("y", block: true)'
  end

  def test_asd_code_becomes_an_inline_svg
    source = %(component "a" { label "A" }\ncomponent "b" { label "B" }\na -> b\n)

    typst = render(result(sections: [{ type: :code, content: source, lang: "asd" }]))

    assert_includes typst, '#image(bytes("<?xml'
    assert_includes typst, 'format: "svg"'
  end

  def test_invalid_asd_falls_back_to_the_source
    typst = render(result(sections: [{ type: :code, content: "this is not asd {{{", lang: "asd" }]))

    assert_includes typst, "Diagram could not be rendered"
    assert_includes typst, '#raw("this is not asd {{{", block: true, lang: "asd")'
  end

  def test_output_compiles_with_typst
    skip "typst CLI not installed" unless system("typst", "--version", out: File::NULL, err: File::NULL)

    sections = [
      { type: :heading, text: NASTY, level: 0 },
      { type: :text, content: "# #{NASTY}\n\n- #{NASTY}\n\n> quote\n\n```ruby\n#{NASTY}\n```\n\n| a | b |\n|---|---|\n| #{NASTY} | 2 |" },
      { type: :table, headers: [NASTY, "B"], rows: [[NASTY, 1]] },
      { type: :list, items: [NASTY, "**#{NASTY}**"] },
      { type: :code, content: NASTY, lang: "text" },
      { type: :code, content: %(component "a" { label "A" }\n), lang: "asd" },
      { type: :message, level: :error, message: NASTY }
    ]
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "out.typ"), render([result(NASTY, sections: sections)]))
      _, err, status = Open3.capture3("typst", "compile", File.join(dir, "out.typ"), File.join(dir, "out.pdf"))

      assert_predicate status, :success?, err
    end
  end
end
