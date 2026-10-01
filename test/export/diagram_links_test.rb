# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "archsight/database"
require "archsight/helpers"
require "archsight/export/confluence/diagram_links"

class ConfluenceDiagramLinksTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "pages"))
    File.write(File.join(@dir, "pages/with-id.md"), "---\nconfluence: https://wiki.example.com/spaces/SP/pages/55/X\n---\n\nx\n")
    File.write(File.join(@dir, "pages/by-title.md"), "---\nconfluence: https://wiki.example.com/display/SP/By+Title\n---\n\nx\n")
    File.write(File.join(@dir, "pages/no-link.md"), "---\ntitle: No link\n---\n\nx\n")
    File.write(File.join(@dir, "pages/broken-link.md"), "---\nconfluence: not a url\n---\n\nx\n")
    File.write(File.join(@dir, "res.yaml"), "apiVersion: architecture/v1alpha1\nkind: ApplicationService\nmetadata:\n  name: Svc\n")
    db = Archsight::Database.new(@dir, compute_annotations: false).tap(&:reload!)
    @links = Archsight::Export::Confluence::DiagramLinks.new(db)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_a_page_with_a_confluence_page_links_there
    assert_equal "https://wiki.example.com/pages/viewpage.action?pageId=55", @links.call("with-id")
    assert_equal "https://wiki.example.com/pages/viewpage.action?pageId=55", @links.call("Page/with-id")
    assert_equal "https://wiki.example.com/display/SP/By+Title", @links.call("by-title"), "a link without a page id is kept as written"
  end

  def test_pages_without_a_usable_link_and_other_resources_are_plain
    assert_nil @links.call("no-link")
    assert_nil @links.call("broken-link")
    assert_nil @links.call("Svc")
    assert_nil @links.call("ApplicationService/Svc")
  end

  def test_unknown_and_ambiguous_references_are_reported_like_in_the_web_ui
    assert_equal :missing, @links.call("Nope")
    assert_equal :missing, @links.call("ApplicationService/with-id")
  end
end
