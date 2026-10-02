# frozen_string_literal: true

require_relative "test_helper"
require "rack/test"
require "archsight/editor"
require "archsight/web/application"

class PageSourceTest < Minitest::Test
  PageSource = Archsight::Editor::PageSource

  SOURCE = <<~MD
    ---
    name: custom-name
    title: Alpha
    tags: one, two
    status: rfc
    toc: yes
    weight: 3
    ---

    # Alpha

    ---

    ```asd
    component "a" {}
    ```
  MD

  def annotations_of(source)
    raw = Archsight::PageLoader.build(path: "alpha.md", source: source, ref: Archsight::LineReference.new("alpha.md", 1))
    raw.dig("metadata", "annotations")
  end

  def test_render_round_trips_an_unchanged_page_byte_for_byte
    assert_equal SOURCE, PageSource.render(annotations: annotations_of(SOURCE), existing_source: SOURCE)
  end

  def test_render_keeps_name_and_unknown_keys_and_replaces_known_ones
    annotations = annotations_of(SOURCE).merge("page/title" => "Beta", "page/status" => "")
    out = PageSource.render(annotations: annotations, existing_source: SOURCE)

    assert_match(/\A---\nname: custom-name\ntitle: Beta\ntags: one, two\ntoc: yes\nweight: 3\n---\n/, out)
    refute_includes out, "status"
  end

  def test_render_separates_a_body_without_leading_newline_and_ends_with_one_newline
    out = PageSource.render(annotations: { "page/title" => "T", "page/content" => "# T\n\ntext\n\n\n" })

    assert_equal "---\ntitle: T\n---\n\n# T\n\ntext\n", out
  end

  def test_render_quotes_values_yaml_would_misread
    out = PageSource.render(annotations: { "page/title" => "yes: really", "page/status" => "no" })

    assert_equal "yes: really", YAML.safe_load(out.split("---\n")[1])["title"]
    assert_equal "no", YAML.safe_load(out.split("---\n")[1])["status"]
  end

  PROPERTIES = <<~MD
    ---
    title: Alpha
    owner: Jane Doe
    created: 2024-01-05T10:00:00Z
    updated: 2024-02-01
    properties:
      Git Repository: https://git.example.com/a
      Note: 'a: b'
    ---

    Body
  MD

  def test_properties_and_timestamps_round_trip_byte_for_byte
    assert_equal PROPERTIES, PageSource.render(annotations: annotations_of(PROPERTIES), existing_source: PROPERTIES)
  end

  def test_properties_are_edited_as_key_value_lines
    annotations = annotations_of(PROPERTIES).merge("page/properties" => "Team: Core\nRepo: https://git.example.com/b")
    meta = YAML.safe_load(PageSource.render(annotations: annotations, existing_source: PROPERTIES).split("---\n")[1], permitted_classes: [Time, Date])

    assert_equal({ "Team" => "Core", "Repo" => "https://git.example.com/b" }, meta["properties"])
  end

  def test_updated_is_set_when_the_page_changes_and_only_then
    now = Time.utc(2026, 10, 2, 9, 30)

    assert_equal PROPERTIES, PageSource.render(annotations: annotations_of(PROPERTIES), existing_source: PROPERTIES, now: now)

    out = PageSource.render(annotations: annotations_of(PROPERTIES).merge("page/title" => "Beta"), existing_source: PROPERTIES, now: now)

    assert_includes out, "updated: 2026-10-02T09:30:00Z\n"
    assert_includes out, "created: 2024-01-05T10:00:00Z\n"
  end

  def test_validate_rejects_broken_frontmatter_missing_frontmatter_and_renames
    assert_raises(Archsight::Editor::FileWriter::WriteError) { PageSource.validate!("no frontmatter", path: "alpha.md", name: "alpha") }
    assert_raises(Archsight::Editor::FileWriter::WriteError) { PageSource.validate!("---\ntitle: x\n", path: "alpha.md", name: "alpha") }
    assert_raises(Archsight::Editor::FileWriter::WriteError) { PageSource.validate!("---\ntitle: [\n---\n", path: "alpha.md", name: "alpha") }
    assert_raises(Archsight::Editor::FileWriter::WriteError) { PageSource.validate!("---\nname: other\n---\n", path: "alpha.md", name: "alpha") }
    PageSource.validate!("---\ntitle: fine\n---\n", path: "alpha.md", name: "alpha")
  end
end

class WholeFileWriterTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "page.md")
    File.write(@path, "old")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_replace_file_replaces_content_and_keeps_mode_without_leaving_temp_files
    File.chmod(0o640, @path)
    Archsight::Editor::FileWriter.replace_file(path: @path, content: "new")

    assert_equal "new", Archsight::Editor::FileWriter.read_file(path: @path)
    assert_equal 0o640, File.stat(@path).mode & 0o777
    assert_equal ["page.md"], Dir.children(@dir)
  end

  def test_replace_file_requires_an_existing_writable_file
    assert_raises(Archsight::Editor::FileWriter::WriteError) do
      Archsight::Editor::FileWriter.replace_file(path: File.join(@dir, "missing.md"), content: "x")
    end
    File.chmod(0o444, @path)
    skip("root ignores file modes") if File.writable?(@path)

    assert_raises(Archsight::Editor::FileWriter::WriteError) { Archsight::Editor::FileWriter.replace_file(path: @path, content: "x") }
  end

  def test_validate_file_detects_a_modified_file
    hash = Archsight::Editor::ContentHasher.hash("old")

    assert_nil Archsight::Editor::ContentHasher.validate_file(path: @path, expected_hash: hash)
    File.write(@path, "changed")

    assert Archsight::Editor::ContentHasher.validate_file(path: @path, expected_hash: hash)[:conflict]
    assert_nil Archsight::Editor::ContentHasher.validate_file(path: @path, expected_hash: nil)
  end
end

class PageEditorRoutesTest < Minitest::Test
  include Rack::Test::Methods

  def app = Archsight::Web::Application

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "alpha.md")
    File.write(@path, "---\ntitle: Alpha\nstatus: rfc\n---\n\n# Alpha\n\nBody\n")
    @previous_db = app.instance_variable_get(:@database)
    app.instance_variable_set(:@database, Archsight::Database.new(@dir).tap(&:reload!))
    @inline_edit = app.settings.inline_edit_enabled
    app.set :inline_edit_enabled, true
  end

  def teardown
    app.set :inline_edit_enabled, @inline_edit
    app.instance_variable_set(:@database, @previous_db)
    FileUtils.rm_rf(@dir)
  end

  def json = JSON.parse(last_response.body)

  def post_json(path, body)
    post path, JSON.generate(body), "CONTENT_TYPE" => "application/json"
  end

  def edit_form
    get "/api/v1/editor/kinds/Page/instances/alpha/form"
    json
  end

  def generate(form, changes = {})
    annotations = form["annotations"].merge(changes)
    post_json "/api/v1/editor/kinds/Page/instances/alpha/generate",
              { name: "alpha", annotations: annotations, content_hash: form["content_hash"] }
    json
  end

  def test_form_describes_a_markdown_page_with_a_content_field_and_no_relations
    form = edit_form

    assert_equal "markdown", form["format"]
    assert_equal @path, form["path_ref"]
    assert_equal "markdown", form["fields"].find { |f| f["key"] == "page/content" }["input_type"]
    assert_empty form["relation_options"]
    assert_equal Archsight::Editor::ContentHasher.hash(File.read(@path)), form["content_hash"]
  end

  def test_generate_returns_markdown_with_frontmatter
    result = generate(edit_form, "page/content" => "# Alpha\n\nChanged")

    assert_equal "markdown", result["format"]
    assert_match(/\A---\ntitle: Alpha\nstatus: rfc\nupdated: \d{4}-\d\d-\d\dT[\d:]+Z\n---\n\n# Alpha\n\nChanged\n\z/, result["yaml"])
  end

  def test_generate_without_changes_reproduces_the_file
    assert_equal File.read(@path), generate(edit_form)["yaml"]
  end

  def test_save_replaces_the_file_and_reloads
    form = edit_form
    source = generate(form, "page/title" => "Renamed", "page/content" => "New body")["yaml"]
    post_json "/api/v1/editor/kinds/Page/instances/alpha/save", { yaml: source, content_hash: form["content_hash"] }

    assert json["success"]
    assert_equal source, File.read(@path)
    assert_equal "Renamed", app.database.instance_by_kind("Page", "alpha").title
  end

  def test_save_is_forbidden_without_inline_edit
    app.set :inline_edit_enabled, false
    post_json "/api/v1/editor/kinds/Page/instances/alpha/save", { yaml: "---\ntitle: x\n---\n" }

    assert_equal 403, last_response.status
    assert_includes File.read(@path), "Alpha"
  end

  def test_save_reports_a_conflict_when_the_file_changed
    form = edit_form
    File.write(@path, "---\ntitle: Someone else\n---\n")
    post_json "/api/v1/editor/kinds/Page/instances/alpha/save", { yaml: "---\ntitle: x\n---\n", content_hash: form["content_hash"] }

    assert_equal 409, last_response.status
    assert json["conflict"]
    assert_includes File.read(@path), "Someone else"
  end

  def test_save_rejects_broken_frontmatter_without_touching_the_file
    before = File.read(@path)
    post_json "/api/v1/editor/kinds/Page/instances/alpha/save", { yaml: "---\ntitle: [\n---\nbody" }

    assert_equal 400, last_response.status
    refute json["success"]
    assert_equal before, File.read(@path)
  end
end
