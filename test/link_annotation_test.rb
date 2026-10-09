# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "archsight/editor/page_source"
require "archsight/export/confluence/diagram_links"

# link/<name> holds a URL on every kind; pages write them as `links:` in the frontmatter
class LinkAnnotationTest < Minitest::Test
  def with_files(files)
    Dir.mktmpdir do |dir|
      files.each { |name, content| File.write(File.join(dir, name), content) }
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def link_annotation(kind)
    Archsight::Resources[kind].annotations.find { |a| a.key == "link/*" }
  end

  def test_every_kind_with_architecture_annotations_and_pages_accept_links
    %w[ApplicationService BusinessActor TechnologyArtifact MotivationRequirement Page].each do |kind|
      annotation = link_annotation(kind)

      assert annotation, "#{kind} has no link/*"
      assert annotation.matches?("link/confluence"), "#{kind} does not match link/confluence"
    end
  end

  def test_a_link_must_be_a_url
    annotation = link_annotation("ApplicationService")

    assert annotation.valid?("https://confluence.example.com/pages/1")
    refute annotation.valid?("see the wiki")
  end

  def test_links_have_no_name_rules_beyond_the_prefix
    annotation = link_annotation("ApplicationService")

    assert annotation.matches?("link/confluence-isms")
    assert annotation.matches?("link/github.com/example")
    refute annotation.matches?("links/confluence")
  end

  def test_a_resource_of_any_kind_can_have_links
    yaml = <<~YAML
      apiVersion: architecture/v1alpha1
      kind: ApplicationService
      metadata:
        name: Foo
        annotations:
          link/confluence: https://confluence.example.com/pages/1
          link/jira: https://jira.example.com/browse/ARCH-1
      spec: {}
    YAML

    with_files("test.yaml" => yaml) do |db|
      assert_empty Archsight::Linter.new(db).validate
      assert_equal %w[link/confluence link/jira], db.instance_by_kind("ApplicationService", "Foo").annotations.keys.grep(%r{\Alink/})
    end
  end

  def test_a_link_that_is_no_url_is_a_lint_error
    yaml = <<~YAML
      apiVersion: architecture/v1alpha1
      kind: ApplicationService
      metadata:
        name: Foo
        annotations:
          link/confluence: somewhere
      spec: {}
    YAML

    with_files("test.yaml" => yaml) do |db|
      errors = Archsight::Linter.new(db).validate

      assert_equal 1, errors.length
      assert_includes errors.first, "link/confluence"
    end
  end

  def test_page_frontmatter_links_become_link_annotations
    page = "---\ntitle: Guide\nlinks:\n  confluence: https://wiki.example.com/spaces/SP/pages/55/Guide\n  jira: https://j.example.com/browse/A-1\n---\n\nbody\n"

    with_files("guide.md" => page) do |db|
      annotations = db.instance_by_kind("Page", "guide").annotations

      assert_equal "https://wiki.example.com/spaces/SP/pages/55/Guide", annotations["link/confluence"]
      assert_equal "https://j.example.com/browse/A-1", annotations["link/jira"]
      refute annotations.key?("page/links")
      assert_empty db.deprecations
    end
  end

  def test_the_old_confluence_key_is_moved_to_the_links_and_reported
    page = "---\ntitle: Guide\nconfluence: https://c.example.com/pages/1\n---\n\nbody\n"

    with_files("guide.md" => page) do |db|
      annotations = db.instance_by_kind("Page", "guide").annotations

      assert_equal "https://c.example.com/pages/1", annotations["link/confluence"]
      refute annotations.key?("page/confluence")
      message = db.deprecations.map(&:message).join

      assert_includes message, "'page/confluence' is renamed to 'link/confluence'"
      assert_includes message, "links: { confluence: <url> }"
    end
  end

  def test_an_explicit_link_wins_over_the_old_key
    page = "---\nconfluence: https://old.example.com/1\nlinks:\n  confluence: https://new.example.com/1\n---\n\nbody\n"

    with_files("guide.md" => page) do |db|
      assert_equal "https://new.example.com/1", db.instance_by_kind("Page", "guide").annotations["link/confluence"]
    end
  end

  def test_the_page_api_data_and_the_exporter_read_the_link
    page = "---\nlinks:\n  confluence: https://wiki.example.com/spaces/SP/pages/55/Guide\n---\n\nbody\n"

    with_files("guide.md" => page) do |db|
      instance = db.instance_by_kind("Page", "guide")

      assert_includes Archsight::Export::Confluence::DiagramLinks.confluence_url(instance), "wiki.example.com"
    end
  end

  def test_saving_a_page_keeps_its_links_and_moves_the_old_key
    source = "---\ntitle: Guide\nconfluence: https://c.example.com/pages/1\nlinks:\n  jira: https://j.example.com/browse/A-1\n---\n\nbody\n"
    annotations = { "page/title" => "Guide", "page/content" => "body" }

    out = Archsight::Editor::PageSource.render(annotations: annotations, existing_source: source)

    assert_includes out, "links:\n  jira: https://j.example.com/browse/A-1\n  confluence: https://c.example.com/pages/1\n"
    refute_match(/^confluence:/, out)
  end
end
