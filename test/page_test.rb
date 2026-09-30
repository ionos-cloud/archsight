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

  def test_menu_cycle
    errors = lint("m1.yaml" => menu("M1", menus: ["M2"]), "m2.yaml" => menu("M2", menus: ["M1"]))

    assert(errors.any? { |e| e.include?("forms a cycle") })
  end
end
