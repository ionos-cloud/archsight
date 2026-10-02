# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "rexml/document"
require "archsight/database"
require "archsight/export"
require "archsight/export/confluence/page_properties"

class ConfluencePagePropertiesTest < Minitest::Test
  PageProperties = Archsight::Export::Confluence::PageProperties

  PAGE = <<~MD
    ---
    title: Props
    status: WIP
    owner: Jane Doe <jane@example.com>
    author: John Smith
    tags: imported, Team:Core, Team:R&D, concept
    created: 2024-01-05T10:00:00Z
    properties:
      Git Repository: https://git.example.com/a?x=1&y=2
      Ticket: "{jira:PROJ-12} and <b>"
    ---

    body
  MD

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "props.md"), PAGE)
    File.write(File.join(@dir, "bare.md"), "---\ntitle: Bare\n---\n\nx\n")
    @db = Archsight::Database.new(@dir, compute_annotations: false).tap(&:reload!)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def page(name) = @db.instances_by_kind("Page").fetch(name)

  def test_frontmatter_becomes_a_page_properties_table
    xml = PageProperties.xml(page("props"))
    REXML::Document.new(%(<root xmlns:ac="a">#{xml}</root>))

    assert_includes xml, %(<ac:structured-macro ac:name="details"><ac:rich-text-body><table><tbody>)
    assert_includes xml, "<tr><th>Document status</th><td><ac:structured-macro ac:name=\"status\"><ac:parameter ac:name=\"colour\">Yellow</ac:parameter><ac:parameter ac:name=\"title\">WIP</ac:parameter>"
    assert_includes xml, "<tr><th>Document owner</th><td>Jane Doe</td></tr>"
    assert_includes xml, "<tr><th>Document author</th><td>John Smith</td></tr>"
    assert_includes xml, "<tr><th>Teams</th><td>Core, R&amp;D</td></tr>"
    assert_includes xml, "<tr><th>Tags</th><td>imported, concept</td></tr>"
  end

  def test_properties_are_rows_with_links_macros_and_escaping
    xml = PageProperties.xml(page("props"))

    assert_includes xml, %(<th>Git Repository</th><td><a href="https://git.example.com/a?x=1&amp;y=2">https://git.example.com/a?x=1&amp;y=2</a></td>)
    assert_includes xml, %(<th>Ticket</th><td><ac:structured-macro ac:name="jira"><ac:parameter ac:name="key">PROJ-12</ac:parameter></ac:structured-macro> and &lt;b&gt;</td>)
  end

  def test_created_and_updated_are_not_exported
    refute_includes PageProperties.xml(page("props")), "2024-01-05"
  end

  def test_a_page_without_properties_gets_no_table
    assert_equal "", PageProperties.xml(page("bare"))
  end

  def test_unknown_status_words_get_a_grey_lozenge
    File.write(File.join(@dir, "odd.md"), "---\ntitle: Odd\nstatus: whatever\n---\n\nx\n")
    @db.reload!

    assert_includes PageProperties.xml(page("odd")), %(<ac:parameter ac:name="colour">Grey</ac:parameter>)
  end

  def test_property_values_are_inline_markdown
    File.write(File.join(@dir, "md.md"), "---\ntitle: Md\nproperties:\n  Notes: \"**bold**, *it*, `code` and [a link](https://git.example.com/x) and https://git.example.com/y\"\n---\n\nx\n")
    @db.reload!
    xml = PageProperties.xml(page("md"))
    REXML::Document.new(%(<root xmlns:ac="a">#{xml}</root>))

    assert_includes xml, "<strong>bold</strong>, <em>it</em>, <code>code</code>"
    assert_includes xml, '<a href="https://git.example.com/x">a link</a>'
    assert_includes xml, '<a href="https://git.example.com/y">https://git.example.com/y</a>'
  end

  def test_raw_html_in_a_property_is_escaped
    xml = PageProperties.xml(page("props"))

    assert_includes xml, "and &lt;b&gt;"
  end
end
