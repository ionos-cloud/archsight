# frozen_string_literal: true

require_relative "pdf_fixture"
require "archsight/pdf/sample_document"

class PdfSampleDocumentTest < Minitest::Test
  include PdfFixture

  def setup = build_resources
  def teardown = cleanup_resources

  def sample(name)
    Archsight::Pdf::SampleDocument.new(@db, @db.instance_by_kind("Config", name), resources_dir: @dir, pdf_images: false)
  end

  def test_the_sample_is_a_cover_and_a_page_in_the_look_of_the_config
    files = sample("Config:PDF:brand").files

    assert_includes files["main.typ"], "#cover-page("
    assert_includes files["main.typ"], '#"Summary"'
    assert_includes files["main.typ"], "#box(fill:" # the status badges
    assert_includes files["theme.typ"], "#aa0000"
    assert_equal PdfFixture::SVG, files["logo.svg"]
  end

  def test_a_part_is_a_document_of_just_that_page
    config = @db.instance_by_kind("Config", "Config:PDF:brand")
    part = ->(name) { Archsight::Pdf::SampleDocument.new(@db, config, part: name, resources_dir: @dir, pdf_images: false) }

    assert_includes part.call("cover").files["main.typ"], "#cover-page("
    refute_includes part.call("cover").files["main.typ"], '#"Summary"'
    refute_includes part.call("page").files["main.typ"], "#cover-page("
    assert_includes part.call("page").files["main.typ"], '#"Summary"'
    assert_includes part.call("nonsense").files["main.typ"], "#cover-page("
    assert_equal %w[preview-Config-PDF-brand-cover.pdf preview-Config-PDF-brand-page.pdf preview-Config-PDF-brand.pdf],
                 %w[cover page].map { |n| part.call(n).filename } + [part.call(nil).filename]
    refute_equal part.call("cover").fingerprint, part.call("page").fingerprint
  end

  def test_the_sample_does_not_depend_on_tags_or_the_default_config
    assert_includes sample("Config:PDF:default").files["theme.typ"], "#112233"
    refute_includes sample("Config:PDF:default").files["theme.typ"], "#aa0000"
  end

  def test_fingerprint_follows_the_config
    before = sample("Config:PDF:default").fingerprint
    File.write(File.join(@dir, "templates.yaml"), PdfFixture::TEMPLATES.sub("#112233", "#445566"))
    @db.reload!

    refute_equal before, sample("Config:PDF:default").fingerprint
  end

  def test_the_sample_compiles
    skip "typst is not installed" unless typst?

    assert Archsight::Pdf.compile(Archsight::Pdf::SampleDocument.new(@db, @db.instance_by_kind("Config", "Config:PDF:brand"), resources_dir: @dir)).start_with?("%PDF")
  end
end
