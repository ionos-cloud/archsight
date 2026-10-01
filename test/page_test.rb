# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "rack/test"
require "json"
require "archsight/web/application"
require "archsight/page_tree"

class PageLoaderTest < Minitest::Test
  REF = Archsight::LineReference.new("x.md", 1)

  def build(source, path: "/root/strategy/lang.md")
    Archsight::PageLoader.build(path: path, source: source, ref: REF)
  end

  def test_plain_markdown_is_ignored
    assert_nil build("# Just a readme\n")
  end

  def test_frontmatter_maps_to_annotations
    page = build(<<~MD)
      ---
      tags: concept, ga
      title: Language Strategy
      status: rfc
      toc: yes
      confluence: https://c.example.com/pages/1
      ---
      # Body
    MD
    annotations = page["metadata"]["annotations"]

    assert_equal "Page", page["kind"]
    assert_equal "lang", page["metadata"]["name"]
    assert_equal "Language Strategy", annotations["page/title"]
    assert_equal "concept, ga", annotations["page/tags"]
    assert_equal "yes", annotations["page/toc"]
    assert_equal "# Body\n", annotations["page/content"]
  end

  def test_name_and_list_tags
    page = build("---\nname: custom\ntags: [a, b]\n---\nx")

    assert_equal "custom", page["metadata"]["name"]
    assert_equal "a, b", page["metadata"]["annotations"]["page/tags"]
  end

  def test_unclosed_frontmatter_raises
    assert_raises(Archsight::ResourceError) { build("---\ntitle: x\n") }
  end

  def test_invalid_yaml_reports_line
    error = assert_raises(Archsight::ResourceError) { build("---\ntitle: [\n---\nx") }

    assert_operator error.ref.line_no, :>, 1
  end
end

class PageDatabaseTest < Minitest::Test
  include Rack::Test::Methods

  def app = Archsight::Web::Application

  def write(dir, name, content)
    path = File.join(dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def with_db
    Dir.mktmpdir do |dir|
      write(dir, "a.md", "---\ntitle: Alpha\ntags: one\ntoc: yes\n---\n# Alpha\n\n## Sub\n\nSee [[Beta|the beta]] and [[Nope]]\n")
      write(dir, "docs/b.md", "---\ntitle: Beta\n---\nBack to [[a]]\n")
      write(dir, "README.md", "no frontmatter")
      write(dir, "orphan.md", "---\ntitle: Orphan\n---\nx")
      write(dir, "menus.yaml", <<~YAML)
        apiVersion: architecture/v1alpha1
        kind: PageMenu
        metadata:
          name: Root
        spec:
          contains:
            pages: [a]
            menus: [Child]
        ---
        apiVersion: architecture/v1alpha1
        kind: PageMenu
        metadata:
          name: Child
          annotations:
            menu/title: The Child
        spec:
          contains:
            pages: [b]
      YAML
      db = Archsight::Database.new(dir)
      db.reload!
      yield db
    end
  end

  def test_loads_pages_and_ignores_plain_markdown
    with_db do |db|
      assert_equal %w[a b orphan], db.instances_by_kind("Page").keys.sort
    end
  end

  def test_page_names_do_not_depend_on_the_resources_root
    Dir.mktmpdir do |dir|
      write(dir, "wiki/strategy/language.md", "---\ntitle: L\n---\nx")

      names = [dir, File.join(dir, "wiki")].map do |root|
        Archsight::Database.new(root).tap(&:reload!).instances_by_kind("Page").keys
      end

      assert_equal [["language"], ["language"]], names
    end
  end

  def test_duplicate_page_names_are_reported
    Dir.mktmpdir do |dir|
      write(dir, "one/x.md", "---\ntitle: One\n---\n1")
      write(dir, "two/x.md", "---\ntitle: Two\n---\n2")

      error = assert_raises(Archsight::ResourceError) { Archsight::Database.new(dir).reload! }

      assert_includes error.message, "already used"
    end
  end

  def test_tags_are_queryable
    with_db do |db|
      assert_equal ["a"], db.query('Page: page/tags == "one"').map(&:name)
    end
  end

  def test_unknown_page_in_menu_fails
    Dir.mktmpdir do |dir|
      write(dir, "m.yaml", "apiVersion: architecture/v1alpha1\nkind: PageMenu\nmetadata:\n  name: M\nspec:\n  contains:\n    pages: [missing]\n")
      write(dir, "a.md", "---\ntitle: A\n---\nx")

      assert_raises(Archsight::ResourceError) { Archsight::Database.new(dir).reload! }
    end
  end

  def test_tree_breadcrumb_and_unsorted
    with_db do |db|
      tree = Archsight::PageTree.new(db)
      nodes = tree.tree

      assert_equal(%w[Root unsorted], nodes.map { |n| n["name"] })
      root = nodes.first

      assert_equal(%w[a Child], root["children"].map { |n| n["name"] })
      assert_equal "The Child", root["children"].last["title"]
      assert_equal(["Orphan"], nodes.last["children"].map { |n| n["title"] })
      assert_equal(%w[Root Child], tree.breadcrumb(db.instance_by_kind("Page", "b")).map { |b| b["name"] })
    end
  end

  def test_home_page_is_not_unsorted_but_others_still_are
    Dir.mktmpdir do |dir|
      write(dir, "home.md", "---\ntitle: Welcome\n---\nx")
      write(dir, "titled.md", "---\ntitle: HOME\n---\nx")
      write(dir, "other.md", "---\ntitle: Other\n---\nx")
      db = Archsight::Database.new(dir)
      db.reload!
      tree = Archsight::PageTree.new(db)

      assert_equal(%w[Other], tree.unsorted_pages.map(&:title))
      assert_equal(["unsorted"], tree.tree.map { |n| n["name"] })
      assert_equal(%w[Other], tree.tree.first["children"].map { |n| n["title"] })
    end
  end

  def test_home_page_in_a_menu_stays_in_the_tree
    Dir.mktmpdir do |dir|
      write(dir, "home.md", "---\ntitle: Home\n---\nx")
      write(dir, "menus.yaml", MENUS.sub("pages: [language-strategy]", "pages: [home]"))
      db = Archsight::Database.new(dir)
      db.reload!
      strategy = Archsight::PageTree.new(db).tree.first["children"].first

      assert_equal(%w[home], strategy["children"].map { |n| n["name"] })
    end
  end

  def test_home_page_prefers_the_name_over_the_title_and_is_nil_without_one
    Dir.mktmpdir do |dir|
      write(dir, "welcome.md", "---\ntitle: Home\n---\nx")
      db = Archsight::Database.new(dir)
      db.reload!

      assert_equal "welcome", Archsight::PageTree.new(db).home_page.name

      write(dir, "home.md", "---\ntitle: Start\n---\nx")
      db.reload!

      assert_equal "home", Archsight::PageTree.new(db).home_page.name
    end
    Dir.mktmpdir do |dir|
      write(dir, "a.md", "---\ntitle: A\n---\nx")
      db = Archsight::Database.new(dir)
      db.reload!

      assert_nil Archsight::PageTree.new(db).home_page
    end
  end

  def test_api_reports_the_home_page
    Dir.mktmpdir do |dir|
      write(dir, "home.md", "---\ntitle: Start here\n---\nx")
      write(dir, "a.md", "---\ntitle: A\n---\nx")
      previous = app.instance_variable_get(:@database)
      app.instance_variable_set(:@database, Archsight::Database.new(dir).tap(&:reload!))
      get "/api/v1/pages"
      body = JSON.parse(last_response.body)

      assert_equal({ "name" => "home", "title" => "Start here" }, body["home"])
      assert_equal(["A"], body["pages"].flat_map { |n| n["children"].map { |c| c["title"] } })
    ensure
      app.instance_variable_set(:@database, previous)
    end
  end

  def test_toc
    toc = Archsight::PageTree.toc("# A\n\n## B\n\n```\n# not a heading\n```\n")

    assert_equal([[1, "a", "A"], [2, "b", "B"]], toc.map { |e| e.values_at("level", "id", "text") })
  end

  def test_wiki_links
    with_db do |db|
      html = Archsight::Helpers::WikiLinks.new(db).render("[[Beta|the beta]] [[a]] [[Nope]] [[<b>]]")

      assert_includes html, '<a href="/pages/b">the beta</a>'
      assert_includes html, '<a href="/pages/a">Alpha</a>'
      assert_includes html, '<span class="broken-link" title="Resource not found">Nope</span>'
      assert_includes html, "&lt;b&gt;"
    end
  end

  STRATEGY = <<~MD
    ---
    tags: concept, ga, requirement
    title: Language Strategy
    author: John Smith <john.smith@example.com>
    status: rfc
    toc: yes
    confluence: https://confluence.example.com/spaces/ARCH/pages/12345/Language+Strategy
    ---

    # Language Strategy

    ## Options

    | Language | Use case |
    |----------|----------|
    | Go       | Services |

    ## Decision

    ## Overview
  MD

  MENUS = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: PageMenu
    metadata:
      name: Handbook
    spec:
      contains:
        menus: [Strategy]
    ---
    apiVersion: architecture/v1alpha1
    kind: PageMenu
    metadata:
      name: Strategy
    spec:
      contains:
        pages: [language-strategy]
  YAML

  def with_application_db
    Dir.mktmpdir do |dir|
      write(dir, "language-strategy.md", STRATEGY)
      write(dir, "menus.yaml", MENUS)
      previous = app.instance_variable_get(:@database)
      app.instance_variable_set(:@database, Archsight::Database.new(dir).tap(&:reload!))
      yield
    ensure
      app.instance_variable_set(:@database, previous)
    end
  end

  def test_api_tree_and_page
    with_application_db do
      get "/api/v1/pages"

      assert_predicate last_response, :ok?
      body = JSON.parse(last_response.body)

      assert_equal "Handbook", body["pages"].first["name"]
      assert_includes body["tags"], { "tag" => "concept", "count" => 1 }

      get "/api/v1/pages/language-strategy"
      data = JSON.parse(last_response.body)

      assert_equal "Language Strategy", data["title"]
      assert_equal %w[concept ga requirement], data["tags"]
      assert_includes data["html"], "<table>"
      assert_equal(%w[Handbook Strategy], data["breadcrumb"].map { |b| b["name"] })
      assert_equal(%w[Options Decision Overview], data["toc"].map { |e| e["text"] })
      refute_includes data["html"], "<h1"
      assert_includes data["confluence"], "confluence.example.com"
      assert_equal({ "name" => "John Smith", "email" => "john.smith@example.com" }, data["author"])

      get "/api/v1/pages/missing"

      assert_equal 404, last_response.status
    end
  end

  # Just enough of JSON Schema for the page schemas: objects (required + declared keys only), arrays,
  # $ref, oneOf and null. Fails on undeclared keys, so the documented API cannot drift from the real one.
  def assert_matches_schema(schema, data, spec, path = "response")
    schema = spec.dig("components", "schemas", schema["$ref"].split("/").last) if schema["$ref"]
    if schema["oneOf"]
      matching = schema["oneOf"].any? do |option|
        assert_matches_schema(option, data, spec, path)
        true
      rescue Minitest::Assertion
        false
      end

      assert matching, "#{path} matches none of the oneOf schemas"
    elsif Array(schema["type"]).include?("null") && data.nil?
      nil
    elsif schema["type"] == "object"
      assert_kind_of Hash, data, path
      Array(schema["required"]).each { |key| assert data.key?(key), "#{path} lacks required key #{key}" }
      extra = data.keys - schema.fetch("properties", {}).keys

      assert_empty extra, "#{path} has keys the spec does not declare"
      data.each { |key, value| assert_matches_schema(schema["properties"][key], value, spec, "#{path}.#{key}") }
    elsif schema["type"] == "array"
      assert_kind_of Array, data, path
      data.each_with_index { |item, i| assert_matches_schema(schema["items"], item, spec, "#{path}[#{i}]") }
    elsif schema["type"] == "integer"
      assert_kind_of Integer, data, path
    elsif Array(schema["type"]).include?("string")
      assert_kind_of String, data, path
    end
  end

  def test_openapi_schemas_describe_the_page_responses
    spec = YAML.load_file(File.expand_path("../lib/archsight/web/api/openapi/spec.yaml", __dir__))
    schema = ->(path, status) { spec.dig("paths", path, "get", "responses", status, "content", "application/json", "schema") }
    with_application_db do
      get "/api/v1/pages"

      assert_matches_schema(schema.call("/api/v1/pages", "200"), JSON.parse(last_response.body), spec, "GET /api/v1/pages")

      get "/api/v1/pages/language-strategy"

      assert_matches_schema(schema.call("/api/v1/pages/{name}", "200"), JSON.parse(last_response.body), spec, "GET /api/v1/pages/{name}")

      get "/api/v1/pages/missing"

      assert_matches_schema(schema.call("/api/v1/pages/{name}", "404"), JSON.parse(last_response.body), spec, "404")
    end
  end

  def test_openapi_page_schemas_accept_a_home_page_and_a_page_without_metadata
    spec = YAML.load_file(File.expand_path("../lib/archsight/web/api/openapi/spec.yaml", __dir__))
    Dir.mktmpdir do |dir|
      write(dir, "home.md", "---\ntitle: Home\n---\nx")
      write(dir, "bare.md", "---\ntags: a\n---\n[[home]]")
      previous = app.instance_variable_get(:@database)
      app.instance_variable_set(:@database, Archsight::Database.new(dir).tap(&:reload!))
      get "/api/v1/pages"
      tree = JSON.parse(last_response.body)

      assert_matches_schema({ "$ref" => "#/components/schemas/PageTreeResponse" }, tree, spec)
      assert_equal "home", tree["home"]["name"]

      get "/api/v1/pages/bare"
      page = JSON.parse(last_response.body)

      assert_matches_schema({ "$ref" => "#/components/schemas/PageResponse" }, page, spec)
      assert_nil page["author"]
      assert_nil page["status"]
      assert_empty page["toc"]
    ensure
      app.instance_variable_set(:@database, previous)
    end
  end

  def test_pages_route_serves_spa
    get "/pages/some-page"

    assert_predicate last_response, :ok?
  end
end

class PageLinterTest < Minitest::Test
  def test_author_must_use_email_schema
    errors = lint("a.md" => "---\nauthor: John Smith (john@example.com)\n---\nx", "m.yaml" => menu("M", pages: ["a"]))

    assert(errors.any? { |e| e.include?("page/author") })
  end

  def lint(files)
    Dir.mktmpdir do |dir|
      files.each { |name, content| File.write(File.join(dir, name), content) }
      db = Archsight::Database.new(dir)
      db.reload!
      Archsight::Linter.new(db).validate
    end
  end

  def menu(name, pages: [], menus: [])
    <<~YAML
      apiVersion: architecture/v1alpha1
      kind: PageMenu
      metadata:
        name: #{name}
      spec:
        contains:
          pages: #{pages}
          menus: #{menus}
    YAML
  end

  def test_clean_pages_pass
    errors = lint("a.md" => "---\ntitle: A\n---\nx", "m.yaml" => menu("M", pages: ["a"]))

    assert_empty errors
  end

  def test_orphan_multi_menu_and_broken_link
    errors = lint("a.md" => "---\ntitle: A\n---\nsee [[Nowhere]]", "b.md" => "---\ntitle: B\n---\nx",
                  "m1.yaml" => menu("M1", pages: ["b"]), "m2.yaml" => menu("M2", pages: ["b"]))

    assert(errors.any? { |e| e.include?("not contained in any PageMenu") })
    assert(errors.any? { |e| e.include?("several PageMenus") })
    assert(errors.any? { |e| e.include?("[[Nowhere]]") })
  end

  def test_home_page_needs_no_menu_but_not_two
    assert_empty lint("home.md" => "---\ntitle: Home\n---\nx")

    errors = lint("home.md" => "---\ntitle: Home\n---\nx", "m1.yaml" => menu("M1", pages: ["home"]), "m2.yaml" => menu("M2", pages: ["home"]))

    assert(errors.any? { |e| e.include?("several PageMenus") })
    assert(lint("other.md" => "---\ntitle: Other\n---\nx").any? { |e| e.include?("not contained in any PageMenu") })
  end

  def test_menu_cycle
    errors = lint("m1.yaml" => menu("M1", menus: ["M2"]), "m2.yaml" => menu("M2", menus: ["M1"]))

    assert(errors.any? { |e| e.include?("forms a cycle") })
  end
end
