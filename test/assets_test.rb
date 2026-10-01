# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "rack/test"
require "json"
require "archsight/assets"
require "archsight/helpers"
require "archsight/linter"
require "archsight/web/application"

class AssetsTest < Minitest::Test
  A = Archsight::Assets

  def test_normalize_resolves_dot_segments
    assert_equal "a/b.png", A.normalize("a/./b.png")
    assert_equal "pages/img/a.png", A.normalize("pages/handbook/../img/a.png")
    assert_equal "a/b", A.normalize("a//b/")
  end

  def test_normalize_rejects_everything_that_could_leave_the_tree
    unsafe = [
      "..", "../x.png", "a/../../b.png", "a/b/../../../c", "a/..", "../../../../etc/passwd",
      "/etc/passwd", "C:/x.png", "c:x.png", "a\\b.png", "a/..\\b", "..\\x.png",
      "a\u0000b.png", "a\nb.png", "a\tb.png", "a\u007fb.png",
      ".hidden/x.png", "a/.git/config", "a/.env", "a/..hidden",
      "", ".", "./", "//", "x" * 1100, "\xff.png".dup.force_encoding("UTF-8")
    ]

    unsafe.each { |path| assert_nil A.normalize(path), path.inspect }
    assert_nil A.normalize(nil)
    assert_nil A.normalize(42)
  end

  def test_references_resolve_against_the_directory_of_the_markdown_file
    assert_equal "pages/img/a.png", A.resolve_reference("../img/a.png", "pages/handbook")
    assert_equal "fop/bar.drawio", A.resolve_reference("../../fop/bar.drawio", "pages/handbook")
    assert_equal "pages/handbook/a.png", A.resolve_reference("a.png", "pages/handbook")
    assert_equal "a.png", A.resolve_reference("a.png", "")
    assert_equal "my folder/x y.png", A.resolve_reference("my%20folder/x%20y.png", "")
    assert_equal "a.png", A.resolve_reference("a.png?raw=1#frag", "")
  end

  def test_a_reference_that_climbs_above_the_root_is_rejected_not_clamped
    assert_nil A.resolve_reference("../../../x.png", "pages/handbook")
    assert_nil A.resolve_reference("../x.png", "")
    assert_nil A.resolve_reference("../../../../../../etc/passwd", "a")
  end

  def test_percent_encoded_traversal_is_decoded_once_and_then_checked
    assert_nil A.resolve_reference("..%2f..%2fx.png", "pages")
    assert_nil A.resolve_reference("%2e%2e/%2e%2e/x.png", "pages")
    assert_nil A.resolve_reference("%2E%2E%2F%2E%2E%2Fx.png", "pages")
    assert_nil A.resolve_reference("%2e%2e%5cx.png", "")
    assert_nil A.resolve_reference("a%00.png", "")
    assert_nil A.resolve_reference("%ff.png", "")
    assert_nil A.resolve_reference("%2fetc%2fpasswd", "")
    # decoded once only: this is a directory literally named "%2e%2e", not a parent
    assert_equal "pages/%2e%2e/x.png", A.resolve_reference("%252e%252e/x.png", "pages")
  end

  def test_external_references_are_not_assets
    ["https://x.y/a.png", "http://x", "data:image/png;base64,AAAA", "//cdn.x/a.png", "/abs.png", "#frag", "?q", "", "  ", "mailto:a@b"].each do |ref|
      assert A.external?(ref)
    end
    ["a.png", "../a.png", "dir/a.png", "my%20dir/a.png"].each { |ref| refute A.external?(ref), ref }
  end

  def test_url_for_encodes_each_segment
    assert_equal "/api/v1/assets/pages/img/a.png", A.url_for("pages/img/a.png")
    assert_equal "/api/v1/assets/my%20folder/x%20y%231.png", A.url_for("my folder/x y#1.png")
  end

  def test_only_the_allowed_types_have_a_content_type
    assert_equal "image/png", A.content_type("x.PNG")
    assert_equal "image/svg+xml", A.content_type("x.svg")
    assert_equal "application/xml", A.content_type("x.drawio")
    assert_raises(KeyError) { A.content_type("x.html") }
    assert A.drawio?("a/b.DRAWIO")
    refute A.drawio?("a/b.png")
  end

  # on disk

  # The resources directory is a subdirectory of a temp dir, so "outside" files can sit next to it
  def with_tree
    Dir.mktmpdir do |outer|
      dir = File.join(outer, "resources")
      FileUtils.mkdir_p(File.join(dir, "pages/img"))
      FileUtils.mkdir_p(File.join(dir, "fop"))
      FileUtils.mkdir_p(File.join(dir, ".git"))
      File.write(File.join(dir, "pages/img/a.png"), "png")
      File.write(File.join(dir, "pages/img/a.txt"), "text")
      File.write(File.join(dir, "pages/img/.hidden.png"), "hidden")
      File.write(File.join(dir, "pages/img/a.png.yaml"), "kind: x")
      File.write(File.join(dir, "fop/bar.drawio"), "<mxfile/>")
      File.write(File.join(dir, "pages/home.md"), "---\ntitle: Home\n---\nx")
      File.write(File.join(dir, "secrets.yaml"), "password: hunter2")
      File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'")
      File.write(File.join(dir, ".env"), "TOKEN=1")
      File.write(File.join(dir, ".git/config"), "[core]")
      File.write(File.join(outer, "secret.png"), "outside the resources directory")
      File.symlink(File.join(outer, "secret.png"), File.join(dir, "link.png"))
      File.symlink(File.join(dir, "pages/img/a.png"), File.join(dir, "pages/img/alias.png"))
      File.symlink(outer, File.join(dir, "up"))
      yield dir
    end
  end

  def test_file_for_serves_regular_files_of_the_allowed_types_inside_the_resources_directory
    with_tree do |dir|
      assert_equal File.realpath(File.join(dir, "pages/img/a.png")), A.file_for("pages/img/a.png", resources_dir: dir)
      assert_equal File.realpath(File.join(dir, "fop/bar.drawio")), A.file_for("fop/bar.drawio", resources_dir: dir)
      assert_equal File.realpath(File.join(dir, "pages/img/a.png")), A.file_for("pages/img/alias.png", resources_dir: dir)
    end
  end

  def test_file_for_never_serves_anything_outside_the_resources_directory
    with_tree do |dir|
      ["../secret.png", "secret.png", "pages/../../secret.png", "../resources/../secret.png", "link.png", "up/secret.png",
       "up/resources/link.png", "pages/img", "pages", "", ".", "missing.png", "/etc/passwd"].each do |path|
        assert_nil A.file_for(path, resources_dir: dir), path.inspect
      end
    end
  end

  def test_resource_definitions_sources_and_hidden_files_are_never_served
    with_tree do |dir|
      ["pages/home.md", "secrets.yaml", "Gemfile", ".env", ".git/config", "pages/img/a.txt", "pages/img/a.png.yaml",
       "pages/img/.hidden.png", "pages/img/noextension"].each do |path|
        assert_nil A.file_for(path, resources_dir: dir), path.inspect
      end
    end
  end

  def test_a_folder_called_assets_is_just_a_folder
    with_tree do |dir|
      FileUtils.mkdir_p(File.join(dir, "assets"))
      File.write(File.join(dir, "assets/x.png"), "png")

      assert_equal File.realpath(File.join(dir, "assets/x.png")), A.file_for("assets/x.png", resources_dir: dir)
      assert_equal "assets/x.png", A.resolve_reference("x.png", "assets")
      assert_nil A.file_for("x.png", resources_dir: dir), "no implicit assets/ prefix"
    end
  end

  def test_file_for_without_a_resources_directory
    Dir.mktmpdir do |dir|
      assert_nil A.file_for("a.png", resources_dir: dir)
      assert_nil A.file_for("a.png", resources_dir: File.join(dir, "nope"))
    end
  end

  def test_problem_tells_type_from_missing
    with_tree do |dir|
      assert_nil A.problem("pages/img/a.png", resources_dir: dir)
      assert_equal :type, A.problem("pages/img/a.txt", resources_dir: dir)
      assert_equal :type, A.problem("pages/img/noextension", resources_dir: dir)
      assert_equal :missing, A.problem("pages/img/gone.png", resources_dir: dir)
      assert_equal :missing, A.problem("link.png", resources_dir: dir), "a symlink out of the tree counts as missing"
    end
  end

  Resource = Struct.new(:path_ref)

  def test_base_dir_is_the_directory_of_the_file_relative_to_the_resources_directory
    with_tree do |dir|
      FileUtils.mkdir_p(File.join(dir, "pages/handbook"))
      page = Resource.new(Archsight::LineReference.new(File.join(dir, "pages/handbook/home.md"), 1))
      root = Resource.new(Archsight::LineReference.new(File.join(dir, "top.yaml"), 3))
      outside = Resource.new(Archsight::LineReference.new(File.join(Dir.tmpdir, "elsewhere.md"), 1))

      assert_equal "pages/handbook", A.base_dir_for(page, resources_dir: dir)
      assert_equal "", A.base_dir_for(root, resources_dir: dir)
      assert_nil A.base_dir_for(outside, resources_dir: dir)
      assert_nil A.base_dir_for(Resource.new(nil), resources_dir: dir)
    end
  end
end

class AssetImagesTest < Minitest::Test
  Images = Archsight::Helpers::AssetImages

  def with_tree
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "pages/img"))
      FileUtils.mkdir_p(File.join(dir, "fop"))
      File.write(File.join(dir, "pages/img/a.png"), "png")
      File.write(File.join(dir, "pages/img/x y.png"), "png")
      File.write(File.join(dir, "fop/bar.drawio"), "<mxfile/>")
      File.write(File.join(dir, "pages/doc.pdf"), "pdf")
      yield dir
    end
  end

  def rewrite(html, dir, base = "pages/handbook")
    Images.rewrite(html, base_dir: base, resources_dir: dir)
  end

  def test_a_relative_image_becomes_an_asset_url
    with_tree do |dir|
      out = rewrite('<p><img src="../img/a.png" alt="A" /></p>', dir)

      assert_includes out, 'src="/api/v1/assets/pages/img/a.png"'
      assert_includes out, 'alt="A"'
      assert_includes out, 'loading="lazy"'
    end
  end

  def test_raw_html_images_with_single_quotes_and_entities_are_handled
    with_tree do |dir|
      out = rewrite("<img alt='x &amp; y' src='../img/x%20y.png'>", dir)

      assert_includes out, 'src="/api/v1/assets/pages/img/x%20y.png"'
      assert_includes out, "alt='x &amp; y'"
    end
  end

  def test_an_asd_file_becomes_an_asd_code_block_with_escaped_source
    with_tree do |dir|
      File.write(File.join(dir, "pages/flow.asd"), %(component "a" { label "A & <B>" }\n))
      out = rewrite('<p><img src="../flow.asd" alt="Flow" /></p>', dir)

      assert_includes out, '<pre><code class="language-asd">component &quot;a&quot; { label &quot;A &amp; &lt;B&gt;&quot; }'
      refute_includes out, "<img"
    end
  end

  def test_an_oversize_or_binary_asd_file_is_a_broken_marker
    with_tree do |dir|
      File.write(File.join(dir, "pages/big.asd"), "x" * (Images::MAX_ASD + 1))
      File.binwrite(File.join(dir, "pages/bin.asd"), "\xff\xfe")

      assert_includes rewrite('<img src="../big.asd" alt="" />', dir), 'class="broken-asset"'
      assert_includes rewrite('<img src="../bin.asd" alt="" />', dir), 'class="broken-asset"'
      assert_includes rewrite('<img src="../nope.asd" alt="" />', dir), "no such file: pages/nope.asd"
    end
  end

  def test_a_drawio_file_becomes_a_placeholder_for_the_viewer
    with_tree do |dir|
      out = rewrite('<img src="../../fop/bar.drawio" alt="Flow &lt;1&gt;" />', dir)

      assert_includes out, '<span class="drawio-diagram" data-drawio-src="/api/v1/assets/fop/bar.drawio" data-drawio-title="Flow &lt;1&gt;">'
      assert_includes out, '<a href="/api/v1/assets/fop/bar.drawio">Flow &lt;1&gt;</a>'
      refute_includes out, "<img"
    end
  end

  def test_urls_are_left_alone
    with_tree do |dir|
      html = '<img src="https://x.y/a.png"><img src="data:image/png;base64,AAAA"><img src="//cdn/a.png"><img src="/abs.png"><img alt="no src">'

      assert_equal html, rewrite(html, dir)
    end
  end

  def test_unsafe_missing_and_unserved_images_become_visible_markers
    with_tree do |dir|
      outside = rewrite('<img src="../../../secret.png" alt="S">', dir)
      missing = rewrite('<img src="../img/gone.png" alt="G">', dir)
      type = rewrite('<img src="../doc.pdf">', dir)

      assert_includes outside, '<span class="broken-asset" title="../../../secret.png: the path leaves the resources directory">S</span>'
      assert_includes missing, "no such file: pages/img/gone.png"
      assert_includes type, "this file type is not served"
      assert_includes type, ">../doc.pdf</span>", "the reference is shown when there is no alt text"
      [outside, missing, type].each { |out| refute_includes out, "<img" }
    end
  end

  def test_markers_escape_what_they_show
    with_tree do |dir|
      out = rewrite('<img src="../img/&quot;&gt;&lt;script&gt;.png" alt="&lt;b&gt;">', dir)

      refute_includes out, "<script>"
      refute_includes out, "<b>"
    end
  end

  def test_code_blocks_are_not_touched
    with_tree do |dir|
      html = Kramdown::Document.new("```\n![x](../img/a.png)\n```\n\nand `<img src=\"../img/a.png\">`", input: "GFM").to_html

      assert_equal html, rewrite(html, dir)
    end
  end

  def test_audit_reports_each_problem_once_per_reference
    with_tree do |dir|
      markdown = "![ok](../img/a.png)\n![out](../../../s.png)\n![gone](../img/gone.png)\n![pdf](../doc.pdf)\n![u](https://x/y.png)\n![d](../../fop/bar.drawio)"
      problems = Images.audit(markdown, base_dir: "pages/handbook", resources_dir: dir)

      assert_equal(%i[outside missing type], problems.map { |p| p[:status] })
      assert_equal "pages/img/gone.png", problems[1][:path]
      assert_equal "../../../s.png", problems.first[:reference]
    end
  end
end

class AssetsApiTest < Minitest::Test
  include Rack::Test::Methods

  def app = Archsight::Web::Application

  def setup
    @outer = Dir.mktmpdir
    @dir = File.join(@outer, "resources")
    FileUtils.mkdir_p(File.join(@dir, "pages/img"))
    FileUtils.mkdir_p(File.join(@dir, "fop"))
    FileUtils.mkdir_p(File.join(@dir, "pages/handbook"))
    File.binwrite(File.join(@dir, "pages/img/a.png"), "\x89PNG fake")
    File.write(File.join(@dir, "pages/img/logo.svg"), '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>')
    File.write(File.join(@dir, "fop/bar.drawio"), "<mxfile><diagram/></mxfile>")
    File.write(File.join(@dir, "pages/page.html"), "<script>alert(1)</script>")
    File.write(File.join(@dir, "secrets.yaml"), <<~YAML)
      apiVersion: architecture/v1alpha1
      kind: ApplicationComponent
      metadata:
        name: Hidden
        annotations:
          architecture/description: password hunter2
    YAML
    File.write(File.join(@outer, "secret.png"), "TOP SECRET")
    File.symlink(File.join(@outer, "secret.png"), File.join(@dir, "link.png"))
    File.write(File.join(@dir, "pages/handbook/home.md"), <<~MD)
      ---
      title: Home
      ---

      ![Photo](../img/a.png)

      ![Flow](../../fop/bar.drawio)

      ![Escape](../../../secret.png)
    MD
    @previous_dir = Archsight.resources_dir
    Archsight.resources_dir = @dir
    @previous_db = app.instance_variable_get(:@database)
    app.instance_variable_set(:@database, Archsight::Database.new(@dir).tap(&:reload!))
  end

  def teardown
    Archsight.resources_dir = @previous_dir
    app.instance_variable_set(:@database, @previous_db)
    FileUtils.rm_rf(@outer)
  end

  def spec_operation(verb)
    spec = YAML.load_file(File.expand_path("../lib/archsight/web/api/openapi/spec.yaml", __dir__))
    spec.dig("paths", "/api/v1/assets/{path}", verb)
  end

  def test_openapi_declares_the_headers_and_statuses_the_endpoint_answers_with
    get "/api/v1/assets/pages/img/logo.svg"
    declared = spec_operation("get").dig("responses", "200", "headers").keys

    served = last_response.headers.keys.map(&:downcase)
    undeclared = %w[etag last-modified cache-control content-disposition x-content-type-options content-security-policy]
                 .select { |h| served.include?(h) } - declared.map(&:downcase)

    assert_empty undeclared
    assert_includes spec_operation("get").dig("responses", "200", "content").keys, last_response.content_type.split(";").first

    get "/api/v1/assets/pages/img/a.png", {}, { "HTTP_RANGE" => "bytes=0-3" }

    assert_equal 206, last_response.status
    assert_includes spec_operation("get")["responses"], "206"
    assert_includes spec_operation("get")["responses"].dig("206", "headers"), "Content-Range"

    head "/api/v1/assets/pages/img/a.png"

    assert_predicate last_response, :ok?
    refute_nil spec_operation("head")
  end

  def test_an_asd_file_is_served_as_the_rendered_svg
    File.write(File.join(@dir, "pages/flow.asd"), %(component "a" { label "Hello" }\n))
    get "/api/v1/assets/pages/flow.asd"

    assert_predicate last_response, :ok?
    assert_equal "image/svg+xml", last_response.content_type.split(";").first
    assert_includes last_response.body, "<svg"
    assert_includes last_response.body, "Hello"
    refute_includes last_response.body, %(label "Hello")
    assert_equal "nosniff", last_response.headers["X-Content-Type-Options"]
    assert_includes last_response.headers["Content-Security-Policy"], "sandbox"
  end

  def test_a_rendered_asd_file_is_cached_until_it_changes
    path = File.join(@dir, "pages/flow.asd")
    File.write(path, %(component "a" { label "One" }\n))
    get "/api/v1/assets/pages/flow.asd"
    etag = last_response.headers["ETag"]
    get "/api/v1/assets/pages/flow.asd", {}, { "HTTP_IF_NONE_MATCH" => etag }

    assert_equal 304, last_response.status

    renders = 0
    original = Archsight::Diagram.method(:render)
    Archsight::Diagram.define_singleton_method(:render) { |*args, **kw| renders += original.call(*args, **kw) }
    begin
      get "/api/v1/assets/pages/flow.asd"
      get "/api/v1/assets/pages/flow.asd"
    ensure
      Archsight::Diagram.define_singleton_method(:render, original)
    end

    assert_equal 0, renders, "unchanged file: served from the render cache"

    File.write(path, %(component "a" { label "Two" }\n))
    get "/api/v1/assets/pages/flow.asd", {}, { "HTTP_IF_NONE_MATCH" => etag }

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Two"
    refute_equal etag, last_response.headers["ETag"]
  end

  def test_an_asd_file_that_does_not_render_is_422_as_documented
    File.write(File.join(@dir, "pages/bad.asd"), "component {{{")
    get "/api/v1/assets/pages/bad.asd"

    assert_equal 422, last_response.status
    assert_equal "DiagramError", JSON.parse(last_response.body)["error"]
    assert_includes spec_operation("get")["responses"], "422"
  end

  def test_an_embedded_asd_file_renders_as_a_diagram_in_the_page
    File.write(File.join(@dir, "pages/flow.asd"), %(component "a" { label "Hello" }\n))
    File.write(File.join(@dir, "pages/handbook/home.md"), "---\ntitle: Home\n---\n\n![Flow](../flow.asd)\n")
    app.instance_variable_set(:@database, Archsight::Database.new(@dir).tap(&:reload!))
    get "/api/v1/pages/home"

    assert_predicate last_response, :ok?
    html = JSON.parse(last_response.body)["html"]

    assert_includes html, '<figure class="asd-diagram">'
    assert_includes html, "Hello"
  end

  def test_openapi_404_shapes_match_the_responses
    get "/api/v1/assets/nope.png"
    json = spec_operation("get").dig("responses", "404", "content")

    assert_equal "NotFound", JSON.parse(last_response.body)["error"]
    assert_equal json.dig("application/json", "example"), JSON.parse(last_response.body)
    assert_includes json.keys, "text/html"
  end

  def with_max_bytes(limit)
    original = Archsight::Assets::MAX_BYTES
    Archsight::Assets.send(:remove_const, :MAX_BYTES)
    Archsight::Assets.const_set(:MAX_BYTES, limit)
    yield
  ensure
    Archsight::Assets.send(:remove_const, :MAX_BYTES)
    Archsight::Assets.const_set(:MAX_BYTES, original)
  end

  def test_a_file_over_the_size_cap_is_413_as_documented
    File.binwrite(File.join(@dir, "pages/img/huge.png"), "x")
    with_max_bytes(0) { get "/api/v1/assets/pages/img/huge.png" }

    assert_equal 413, last_response.status
    assert_equal spec_operation("get").dig("responses", "413", "content", "application/json", "example"),
                 JSON.parse(last_response.body).slice("error", "message")
  end

  def test_serves_an_image_with_safe_headers_and_revalidation
    get "/api/v1/assets/pages/img/a.png"

    assert_predicate last_response, :ok?
    assert_equal "\x89PNG fake".b, last_response.body.b
    assert_equal "image/png", last_response.content_type.split(";").first
    assert_equal "nosniff", last_response.headers["X-Content-Type-Options"]
    assert_includes last_response.headers["Cache-Control"], "must-revalidate"
    etag = last_response.headers["ETag"]

    refute_nil etag

    get "/api/v1/assets/pages/img/a.png", {}, { "HTTP_IF_NONE_MATCH" => etag }

    assert_equal 304, last_response.status
  end

  def test_an_svg_gets_a_policy_that_forbids_script_when_opened_directly
    get "/api/v1/assets/pages/img/logo.svg"

    assert_equal "image/svg+xml", last_response.content_type.split(";").first
    assert_includes last_response.headers["Content-Security-Policy"], "default-src 'none'"
    assert_includes last_response.headers["Content-Security-Policy"], "sandbox"
  end

  def test_a_drawio_file_is_served_as_xml_and_head_works
    get "/api/v1/assets/fop/bar.drawio"

    assert_equal "application/xml", last_response.content_type.split(";").first

    head "/api/v1/assets/fop/bar.drawio"

    assert_predicate last_response, :ok?
    assert_empty last_response.body
  end

  def test_outside_missing_and_unserved_files_all_get_the_same_not_found
    bodies = ["secret.png", "link.png", "pages/img/gone.png", "pages/page.html", "pages", "pages/img/a.png/x", "secrets.yaml", "pages/handbook/home.md", ".env"].map do |path|
      get "/api/v1/assets/#{path}"

      assert_equal 404, last_response.status, path
      refute_includes last_response.body, "TOP SECRET"
      assert_equal "NotFound", JSON.parse(last_response.body)["error"], path
      last_response.body
    end

    assert_equal 1, bodies.uniq.size, "the answer must not tell outside from missing"
    refute_includes bodies.first, @dir, "no paths in errors"
  end

  def test_traversal_attempts_never_return_a_file_from_outside
    ["../secret.png", "..%2fsecret.png", "%2e%2e/secret.png", "%2e%2e%2fsecret.png", "pages/img/..%2f..%2f..%2fsecret.png",
     "pages/img/%2e%2e/%2e%2e/%2e%2e/secret.png", "..%5csecret.png", "%252e%252e/secret.png", "pages/img/a.png%00.txt",
     "....//secret.png", "pages//..//..//secret.png"].each do |path|
      get "/api/v1/assets/#{path}"

      refute_equal 200, last_response.status, path
      refute_includes last_response.body, "TOP SECRET", path
    end
  end

  def test_only_get_and_head
    post "/api/v1/assets/pages/img/a.png", "x"

    assert_includes [404, 405], last_response.status

    delete "/api/v1/assets/pages/img/a.png"

    assert_includes [404, 405], last_response.status
    assert_path_exists File.join(@dir, "pages/img/a.png")
  end

  def test_a_page_renders_its_images_as_assets
    get "/api/v1/pages/home"
    html = JSON.parse(last_response.body)["html"]

    assert_includes html, 'src="/api/v1/assets/pages/img/a.png"'
    assert_includes html, 'data-drawio-src="/api/v1/assets/fop/bar.drawio"'
    assert_includes html, 'class="broken-asset"'
    refute_includes html, "secret.png\" "
  end

  def test_the_description_of_a_resource_resolves_images_against_its_yaml_file
    FileUtils.mkdir_p(File.join(@dir, "components"))
    File.write(File.join(@dir, "components/box.png"), "png")
    File.write(File.join(@dir, "components/c.yaml"), <<~YAML)
      apiVersion: architecture/v1alpha1
      kind: ApplicationComponent
      metadata:
        name: Widget
        annotations:
          architecture/description: |
            ![Box](box.png)
    YAML
    app.instance_variable_set(:@database, Archsight::Database.new(@dir).tap(&:reload!))

    get "/api/v1/kinds/ApplicationComponent/instances/Widget"
    description = JSON.parse(last_response.body).dig("metadata", "annotations", "architecture/description")

    assert_includes description, 'src="/api/v1/assets/components/box.png"'
  end
end

class AssetsLintTest < Minitest::Test
  def lint(files)
    Dir.mktmpdir do |dir|
      files.each do |name, content|
        FileUtils.mkdir_p(File.dirname(File.join(dir, name)))
        File.write(File.join(dir, name), content)
      end
      db = Archsight::Database.new(dir)
      db.reload!
      Archsight::Linter.new(db).validate
    end
  end

  PAGE = "---\ntitle: Home\n---\n\n![a](../img/a.png)\n![b](../../../etc/passwd.png)\n![c](../doc.pdf)\n![ok](https://x.y/a.png)\n"

  def test_missing_unsafe_and_unserved_images_are_reported
    errors = lint("pages/handbook/home.md" => PAGE, "pages/doc.pdf" => "pdf")

    assert(errors.any? { |e| e.include?("home.md") && e.include?(%(references asset "../img/a.png" that does not exist (pages/img/a.png))) })
    assert(errors.any? { |e| e.include?(%(references asset "../../../etc/passwd.png" outside the resources directory)) })
    assert(errors.any? { |e| e.include?('references "../doc.pdf", a file type that is not served (.png') })
    refute(errors.any? { |e| e.include?("https://x.y/a.png") })
  end

  def test_embedded_asd_files_must_render
    page = "---\ntitle: Home\n---\n\n![ok](../ok.asd)\n![bad](../bad.asd)\n![gone](../gone.asd)\n"
    errors = lint("pages/handbook/home.md" => page, "pages/ok.asd" => %(component "a" { label "A" }\n), "pages/bad.asd" => "component {{{")

    assert(errors.any? { |e| e.include?("Diagram error") && e.include?("pages/bad.asd") })
    assert(errors.any? { |e| e.include?("that does not exist (pages/gone.asd)") })
    refute(errors.any? { |e| e.include?("ok.asd") })
  end

  def test_existing_images_pass
    errors = lint("pages/handbook/home.md" => "---\ntitle: Home\n---\n\n![a](../img/a.png)\n", "pages/img/a.png" => "png")

    refute(errors.any? { |e| e.include?("asset") })
  end

  def test_the_description_of_a_yaml_resource_is_checked_against_its_own_folder
    yaml = "apiVersion: architecture/v1alpha1\nkind: ApplicationComponent\nmetadata:\n  name: W\n  annotations:\n    architecture/description: |\n      ![x](box.png)\n"

    assert(lint("components/c.yaml" => yaml).any? { |e| e.include?("that does not exist (components/box.png)") })
    refute(lint("components/c.yaml" => yaml, "components/box.png" => "png").any? { |e| e.include?("asset") })
  end
end

class AssetsNextToResourcesTest < Minitest::Test
  def test_yaml_and_markdown_next_to_images_are_still_resources_and_images_are_not
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "assets/data"))
      File.write(File.join(dir, "assets/data/notes.md"), "---\ntitle: Notes\n---\nx")
      File.write(File.join(dir, "real.md"), "---\ntitle: Real\n---\n![x](diagram.drawio) ![y](pic.png)")
      File.write(File.join(dir, "diagram.drawio"), "<mxfile/>")
      File.write(File.join(dir, "pic.png"), "png")
      db = Archsight::Database.new(dir)
      db.reload!

      assert_equal %w[notes real], db.instances_by_kind("Page").keys.sort
      refute(Archsight::Linter.new(db).validate.any? { |e| e.include?("references asset") || e.include?("references \"") }, "references to the images next to it resolve")
    end
  end
end
