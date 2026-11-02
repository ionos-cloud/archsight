# frozen_string_literal: true

require_relative "pdf_fixture"

class PdfDocumentTest < Minitest::Test
  include PdfFixture

  def setup = build_resources
  def teardown = cleanup_resources

  def document(kind, name, **)
    Archsight::Pdf::Document.new(@db, @db.instance_by_kind(kind, name), resources_dir: @dir, pdf_images: false, **)
  end

  def test_page_tags_steer_the_layout
    main = document("Page", "handbook").files["main.typ"]

    assert_includes main, "#cover-page("
    assert_includes main, "#toc-page("
    assert_includes main, 'version: "2.1"'
    assert_includes main, 'classification: "Confidential"'
    assert_includes main, 'owner: "Pat Example"'
    assert_includes main, 'date: "2026-05-04"'
  end

  def test_template_tag_selects_the_template
    theme = document("Page", "handbook").files["theme.typ"]

    assert_includes theme, "#aa0000"
    assert_includes theme, 'logo: "logo.svg"'
  end

  def test_template_option_beats_the_tag
    assert_includes document("Page", "handbook", template: "default").files["theme.typ"], "#112233"
  end

  def test_logo_and_image_are_staged
    files = document("Page", "handbook").files

    assert_equal PdfFixture::SVG, files["logo.svg"]
    assert_equal PdfFixture::SVG, files["img-1.svg"]
    assert_includes files["main.typ"], '#fit-image("img-1.svg")'
  end

  def test_the_title_heading_is_not_repeated_and_links_show_their_label
    main = document("Page", "handbook").files["main.typ"]

    refute_includes main, '#heading(level: 1)[#"Handbook"]'
    assert_includes main, '#"Other"'
  end

  def test_draft_tag_and_option
    assert_includes document("Page", "handbook", draft: true).files["main.typ"], "draft: true"
    assert_includes document("Page", "handbook").files["main.typ"], "draft: false"
  end

  def test_resource_becomes_a_generated_document
    doc = document("ApplicationComponent", "Billing")
    main = doc.files["main.typ"]

    assert_includes main, '#heading(level: 1)[#"Properties"]'
    assert_includes main, "#toc-page("
    assert_includes main, '#emph[#"invoices"]'
    assert_equal "Billing.pdf", doc.filename
  end

  def test_fingerprint_follows_the_content
    before = document("Page", "handbook").fingerprint
    File.write(File.join(@dir, "pages", "handbook.md"), PdfFixture::PAGE.sub("Some", "Other"))
    @db.reload!

    refute_equal before, document("Page", "handbook").fingerprint
  end

  def test_filename_is_safe
    page = @db.instance_by_kind("Page", "handbook")
    page.metadata["name"] = "a b/../c\"d"

    assert_equal "a-b-..-c-d.pdf", Archsight::Pdf::Document.new(@db, page, resources_dir: @dir, pdf_images: false).filename
  end
end
