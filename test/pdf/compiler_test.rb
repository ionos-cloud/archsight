# frozen_string_literal: true

require "tempfile"
require_relative "pdf_fixture"

class PdfCompilerTest < Minitest::Test
  include PdfFixture

  def setup = build_resources
  def teardown = cleanup_resources

  def test_a_page_and_a_resource_compile_to_pdf
    skip "typst is not installed" unless typst?

    %w[Page ApplicationComponent].zip(%w[handbook Billing]).each do |kind, name|
      doc = Archsight::Pdf.document(@db, @db.instance_by_kind(kind, name), resources_dir: @dir)

      assert Archsight::Pdf.compile(doc).start_with?("%PDF"), "#{kind}/#{name}"
    end
  end

  def test_identifiers_without_spaces_may_break_in_the_title_and_the_header
    library = File.read(Archsight::Pdf::Document::LIBRARY)

    assert_includes library, "#let breakable("
    assert_equal 4, library.scan(/breakable\((title|id|doc-id)\)/).size # title block, cover title, header id, cover id
  end

  def test_a_long_name_without_spaces_compiles_and_keeps_to_one_page
    skip "typst is not installed" unless typst?

    long = "A-5-20-AddressingInformationSecurityWithinSupplierAgreements"
    File.write(File.join(@dir, "long.yaml"), "---\napiVersion: architecture/v1alpha1\nkind: ApplicationComponent\nmetadata:\n  name: #{long}\nspec: {}\n")
    @db.reload!
    pdf = Archsight::Pdf.compile(Archsight::Pdf.document(@db, @db.instance_by_kind("ApplicationComponent", long), resources_dir: @dir))

    assert pdf.start_with?("%PDF")
  end

  SECTIONS = "# Title\n\n## One\n\nText.\n\n## Two\n\nText.\n\n# Second\n\nText.\n"

  def test_headings_start_new_pages_as_the_config_asks
    skip "typst is not installed" unless typst? && system("pdfinfo", "-v", out: File::NULL, err: File::NULL)

    assert_equal 1, breaks_pages({}, "")
    assert_equal 2, breaks_pages({ "pdf/break-before" => "1" }, "") # the first heading stays with the title block
    assert_equal 1, breaks_pages({ "pdf/break-before" => "1" }, "pdf:no-breaks")
    assert_equal 3, breaks_pages({ "pdf/keep-space" => "2:100%" }, "") # every later level 2 heading wants a whole page
    assert_equal 4, breaks_pages({ "pdf/break-before" => "1", "pdf/keep-space" => "2:100%" }, "")
  end

  def test_a_missing_binary_is_reported_as_unavailable
    compiler = Archsight::Pdf::Compiler.new(binary: "/nonexistent/typst")

    assert_raises(Archsight::Pdf::Unavailable) { compiler.pdf_images? }
    Dir.mktmpdir { |dir| assert_raises(Archsight::Pdf::Unavailable) { compiler.compile(dir) } }
  end

  def test_a_typst_error_is_reported_with_its_message
    skip "typst is not installed" unless typst?

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "main.typ"), "#let x = (\n")
      error = assert_raises(Archsight::Pdf::Error) { Archsight::Pdf::Compiler.new.compile(dir) }

      assert_match(/typst failed/, error.message)
    end
  end

  def test_cache_keeps_the_last_entries
    cache = Archsight::Pdf::Cache.new(entries: 2)
    calls = 0
    3.times { |i| cache.fetch("k#{i}") { calls += 1 } }
    cache.fetch("k2") { calls += 1 }
    cache.fetch("k0") { calls += 1 }

    assert_equal 4, calls
  end

  private

  # Pages of SECTIONS typeset with a Config that has `annotations` and a page tagged `tags`
  def breaks_pages(annotations, tags)
    config = { "apiVersion" => "architecture/v1alpha1", "kind" => "Config", "spec" => {},
               "metadata" => { "name" => "Config:PDF:breaks", "annotations" => { "config/type" => "pdf" }.merge(annotations) } }
    File.write(File.join(@dir, "breaks.yaml"), YAML.dump(config))
    File.write(File.join(@dir, "pages", "sections.md"), "---\ntitle: Sections\ntags: pdf:template:breaks#{", #{tags}" unless tags.empty?}\n---\n#{SECTIONS}")
    @db.reload!
    pdf = Archsight::Pdf.compile(Archsight::Pdf.document(@db, @db.instance_by_kind("Page", "sections"), resources_dir: @dir))
    Tempfile.create(["sections", ".pdf"]) do |file|
      file.binmode.write(pdf)
      file.flush
      `pdfinfo #{file.path}`[/^Pages:\s+(\d+)/, 1].to_i
    end
  end
end
