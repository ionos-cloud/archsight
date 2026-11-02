# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "rack/test"
require "json"
require "archsight/slides"
require "archsight/linter"
require "archsight/web/application"

class SlidesTest < Minitest::Test
  include Rack::Test::Methods

  def app = Archsight::Web::Application

  def setup
    @outer = Dir.mktmpdir
    @dir = File.join(@outer, "resources")
    FileUtils.mkdir_p(File.join(@dir, "slides/talk"))
    File.binwrite(File.join(@dir, "slides/talk/deck.pdf"), "%PDF-1.4 fake")
    File.write(File.join(@dir, "slides/talk/deck.html"), "<script>document.title = 1</script>")
    File.binwrite(File.join(@dir, "slides/talk/cover.png"), "\x89PNG fake")
    File.write(File.join(@dir, "slides/talk/notes.txt"), "text")
    File.write(File.join(@dir, "secrets.yaml"), <<~YAML)
      apiVersion: architecture/v1alpha1
      kind: ApplicationComponent
      metadata:
        name: Hidden
    YAML
    File.write(File.join(@outer, "outside.pdf"), "%PDF secret")
    File.symlink(File.join(@outer, "outside.pdf"), File.join(@dir, "slides/talk/link.pdf"))
    write_page("pdf-talk", "slides: deck.pdf\ncover: cover.png")
    write_page("html-talk", "slides: deck.html")
    write_page("plain", nil)
    File.write(File.join(@dir, "slides/menu.yaml"), <<~YAML)
      apiVersion: architecture/v1alpha1
      kind: PageMenu
      metadata:
        name: Slides
      spec:
        contains:
          pages: [pdf-talk, html-talk, plain]
    YAML
    @env = ENV.to_h.slice("ARCHSIGHT_SLIDES_SCRIPT_HOSTS", "ARCHSIGHT_CONFIG")
    ENV["ARCHSIGHT_CONFIG"] = File.join(@outer, "none.yaml")
    ENV.delete("ARCHSIGHT_SLIDES_SCRIPT_HOSTS")
    @previous_dir = Archsight.resources_dir
    Archsight.resources_dir = @dir
    @previous_db = app.instance_variable_get(:@database)
    @db = Archsight::Database.new(@dir).tap(&:reload!)
    app.instance_variable_set(:@database, @db)
  end

  def teardown
    %w[ARCHSIGHT_SLIDES_SCRIPT_HOSTS ARCHSIGHT_CONFIG].each { |k| @env.key?(k) ? ENV[k] = @env[k] : ENV.delete(k) }
    Archsight.resources_dir = @previous_dir
    app.instance_variable_set(:@database, @previous_db)
    FileUtils.rm_rf(@outer)
  end

  def write_page(name, extra)
    File.write(File.join(@dir, "slides/talk/#{name}.md"), "---\ntitle: #{name}\n#{extra}\n---\nSummary of #{name}.\n")
  end

  def page(name) = @db.instance_by_kind("Page", name)

  def test_a_pdf_deck_is_served_inline_without_a_policy
    get "/api/v1/decks/slides/talk/deck.pdf"

    assert_predicate last_response, :ok?
    assert_equal "application/pdf", last_response.content_type
    assert_equal "nosniff", last_response.headers["X-Content-Type-Options"]
    assert_nil last_response.headers["Content-Security-Policy"]
  end

  def test_an_html_deck_is_only_served_sandboxed_without_same_origin
    get "/api/v1/decks/slides/talk/deck.html"

    assert_predicate last_response, :ok?
    assert_equal "text/html;charset=utf-8", last_response.content_type.delete(" ")
    csp = last_response.headers["Content-Security-Policy"]

    assert_match(/\Asandbox allow-scripts allow-popups;/, csp)
    refute_includes csp, "allow-same-origin"
    assert_includes csp, "default-src 'none'"
    assert_includes csp, "connect-src blob: data:"
    assert_includes csp, "https://unpkg.com"
  end

  def test_script_hosts_come_from_the_setting_and_only_https_hosts_count
    ENV["ARCHSIGHT_SLIDES_SCRIPT_HOSTS"] = "https://cdn.example.com, http://insecure.example.com https://a.example.com:8443 *"

    assert_equal %w[https://cdn.example.com https://a.example.com:8443], Archsight::Slides.script_hosts
    get "/api/v1/decks/slides/talk/deck.html"

    assert_includes last_response.headers["Content-Security-Policy"], "script-src 'unsafe-inline' 'unsafe-eval' blob: data: https://cdn.example.com"
    refute_includes last_response.headers["Content-Security-Policy"], "unpkg"
  end

  def test_nothing_else_is_served_as_a_deck
    ["slides/talk/cover.png", "slides/talk/notes.txt", "slides/talk/pdf-talk.md", "secrets.yaml", "slides/talk/link.pdf",
     "slides/talk/nope.pdf", "../outside.pdf", "slides/%2e%2e/%2e%2e/outside.pdf"].each do |path|
      get "/api/v1/decks/#{path}"

      assert_equal 404, last_response.status, path
    end
  end

  def test_decks_are_not_assets_and_not_images
    get "/api/v1/assets/slides/talk/deck.html"

    assert_equal 404, last_response.status
    get "/api/v1/assets/slides/talk/deck.pdf"

    assert_equal 404, last_response.status
  end

  def test_the_page_api_names_the_deck_and_the_cover
    get "/api/v1/pages/pdf-talk"
    slides = JSON.parse(last_response.body)["slides"]

    assert_equal({ "url" => "/api/v1/decks/slides/talk/deck.pdf", "filename" => "deck.pdf", "type" => "pdf",
                   "cover_url" => "/api/v1/assets/slides/talk/cover.png" }, slides)
    get "/api/v1/pages/html-talk"

    assert_equal "html", JSON.parse(last_response.body).dig("slides", "type")
    assert_nil JSON.parse(last_response.body).dig("slides", "cover_url")
    get "/api/v1/pages/plain"

    assert_nil JSON.parse(last_response.body)["slides"]
  end

  def test_an_unservable_reference_is_no_deck
    %w[notes.txt ../../secrets.yaml missing.pdf link.pdf deck.html/..].each do |reference|
      write_page("pdf-talk", "slides: #{reference}")
      @db.reload!

      assert_nil Archsight::Slides.for_page(page("pdf-talk"), resources_dir: @dir), reference
    end
  end

  def test_the_linter_reports_a_bad_deck_or_cover
    write_page("pdf-talk", "slides: notes.txt\ncover: gone.png")
    write_page("html-talk", "slides: ../../../outside.pdf")
    @db.reload!
    errors = Archsight::Linter.new(@db).validate.join("\n")

    assert_includes errors, "page/slides \"notes.txt\" must be .pdf, .html"
    assert_includes errors, "page/cover \"gone.png\" does not exist"
    assert_includes errors, "page/slides \"../../../outside.pdf\" is not a path inside the resources directory"
  end

  def test_the_linter_accepts_valid_decks
    errors = Archsight::Linter.new(@db).validate.grep(/slides|cover/)

    assert_empty errors
  end
end
