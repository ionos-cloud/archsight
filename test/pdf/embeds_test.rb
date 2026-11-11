# frozen_string_literal: true

require_relative "pdf_fixture"

class PdfEmbedsTest < Minitest::Test
  include PdfFixture

  EXTRA = <<~'YAML'
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Shipping
      annotations:
        architecture/description: Ships *parcels*.
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: View
    metadata:
      name: View:Components
      annotations:
        view/query: 'ApplicationComponent:'
        view/fields: name,architecture/description
        view/type: list:name
        view/sort: name
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: View
    metadata:
      name: View:Broken
      annotations:
        view/query: 'this is ( not a query'
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationGoal
    metadata:
      name: Goal:Simple
      annotations:
        architecture/description: |
          Keep things **simple**.
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: Analysis
    metadata:
      name: Analysis:Count
      annotations:
        analysis/handler: ruby
        analysis/timeout: 10s
        analysis/script: |
          heading("Totals")
          text("Found **#{instances(:ApplicationComponent).count}** components, see [[Billing]].")
          table(headers: ["Name", "Kind"], rows: instances(:ApplicationComponent).map { |c| [name(c), "ApplicationComponent"] })
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: Analysis
    metadata:
      name: Analysis:Failing
      annotations:
        analysis/handler: ruby
        analysis/script: |
          raise "boom"
    spec: {}
  YAML

  VIEW_BLOCK = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: View
    metadata:
      name: Inline components
      annotations:
        view/query: 'ApplicationComponent:'
        view/type: list:name
  YAML

  def setup
    build_resources
    File.write(File.join(@dir, "extra.yaml"), EXTRA)
    @db.reload!
  end

  def teardown = cleanup_resources

  def embeds(**)
    markdown = nil
    embeds = Archsight::Pdf::Embeds.new(@db, markdown: ->(inline, text) { markdown.render(text, inline: inline) }, **)
    markdown = Archsight::Pdf::Markdown.new
    embeds
  end

  def render(source, **)
    Archsight::Pdf::Markdown.new(embeds: embeds(**)).render(source)
  end

  def test_a_view_on_its_own_line_is_its_table
    out = render("![[View/View:Components]]")

    assert_includes out, '#strong[#"View:Components"]'
    assert_includes out, '#"(2 items)"'
    assert_includes out, "table.header("
    assert_includes out, '#"Billing"'
    assert_includes out, '#"Shipping"'
  end

  def test_view_tables_leave_rules_and_padding_to_the_layout
    out = render("![[View/View:Components]]")

    refute_includes out, "stroke:"
    refute_includes out, "inset:"
    refute_includes out, "#strong[#\"Name\"]" # the layout makes the header semibold
  end

  def test_consecutive_embed_lines_are_all_rendered
    out = render("![[View/View:Components]]\n![[MotivationGoal/Goal:Simple]]")

    assert_includes out, "table.header("
    assert_includes out, '#strong[#"simple"]'
  end

  def test_an_embed_inside_a_sentence_stays_its_label
    out = render("see ![[View/View:Components]] here")

    refute_includes out, "table.header("
    assert_includes out, '#emph[#"View/View:Components"]'
  end

  def test_an_inline_view_block_is_a_table_and_a_broken_one_is_a_visible_note
    ok = render("```view\n#{VIEW_BLOCK}\n```")

    assert_includes ok, "table.header("

    bad = render("```view\nview/query: 'this is ( not a query'\n```")

    assert_includes bad, "view block:"
    assert_includes bad, "#block(fill:"
  end

  def test_a_broken_view_resource_is_a_note
    assert_includes render("![[View/View:Broken]]"), "view View:Broken:"
  end

  def test_requirements_block_is_a_table_or_a_note
    assert_includes render("```requirements\nof: 'ApplicationComponent:'\n```"), "No requirements"
    assert_includes render("```requirements\nnope: 1\n```"), "requirements block:"
  end

  def test_other_kinds_embed_their_description
    out = render("![[MotivationGoal/Goal:Simple]]")

    assert_includes out, '#strong[#"simple"]'
  end

  def test_unknown_and_ambiguous_references_are_notes
    assert_includes render("![[View/Nope]]"), "not found"
  end

  def test_an_analysis_is_run_and_its_sections_are_the_content
    out = render("![[Analysis/Analysis:Count]]")

    assert_match(/#source-note\(theme: theme\)\[#"Analysis:Count"\]\z/, out.strip, "the name is a note below the result")
    refute_includes out, '#strong[#"Analysis:Count"]'
    assert_includes out, "#heading(level: 2)"
    assert_includes out, '#"Totals"'
    assert_includes out, "table.header("
    assert_includes out, '#"Shipping"'
  end

  def test_a_failing_analysis_shows_its_error
    assert_includes render("![[Analysis/Analysis:Failing]]"), "boom"
  end

  def test_analyses_are_limited_per_document
    out = render("![[Analysis/Analysis:Count]]\n\n![[Analysis/Analysis:Failing]]", max_analyses: 1)

    assert_includes out, "at most 1 analyses per document"
  end

  def test_analysis_results_are_reused_for_a_minute
    analysis = @db.instance_by_kind("Analysis", "Analysis:Count")
    now = Time.now
    first = Archsight::Pdf::Embeds.result(@db, analysis, now: now)

    assert_same first, Archsight::Pdf::Embeds.result(@db, analysis, now: now + 30)
    refute_same first, Archsight::Pdf::Embeds.result(@db, analysis, now: now + 120)
  end

  def test_document_contains_the_embeds_and_its_fingerprint_follows_the_data
    page = <<~MD
      ---
      title: Report
      ---
      ![[View/View:Components]]
    MD
    File.write(File.join(@dir, "pages", "report.md"), page)
    @db.reload!
    document = -> { Archsight::Pdf::Document.new(@db, @db.instance_by_kind("Page", "report"), resources_dir: @dir, pdf_images: false) }
    before = document.call

    assert_includes before.files["main.typ"], '#"Shipping"'

    File.write(File.join(@dir, "extra.yaml"), EXTRA.sub("name: Shipping", "name: Shipping2"))
    @db.reload!

    refute_equal before.fingerprint, document.call.fingerprint
  end

  def test_everything_compiles
    skip "typst is not installed" unless typst?

    File.write(File.join(@dir, "pages", "all.md"), <<~MD)
      ---
      title: All
      ---
      ![[View/View:Components]]

      ![[Analysis/Analysis:Count]]

      ![[MotivationGoal/Goal:Simple]]

      ![[Analysis/Analysis:Failing]]

      ```view
      #{VIEW_BLOCK}
      ```

      ```requirements
      of: 'ApplicationComponent:'
      ```

      ```mermaid
      graph TD; A-->B
      ```

      | a | b |
      |:--|--:|
      | 1 | 2 |

      Issue {jira:PROJ-12} done {emoticon:2705} {status:green ok}<br>next
    MD
    @db.reload!
    doc = Archsight::Pdf.document(@db, @db.instance_by_kind("Page", "all"), resources_dir: @dir)

    assert Archsight::Pdf.compile(doc).start_with?("%PDF")
  end
end
