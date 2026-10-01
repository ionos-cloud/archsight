# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "rack/test"
require "json"
require "archsight/web/application"

class EmbedsTest < Minitest::Test
  include Rack::Test::Methods

  def app = Archsight::Web::Application

  RESOURCES = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: View
    metadata:
      name: Services
      annotations:
        view/query: "ApplicationService:"
    ---
    apiVersion: architecture/v1alpha1
    kind: Analysis
    metadata:
      name: Check
      annotations:
        analysis/script: "heading 'x'"
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Svc
  YAML

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "res.yaml"), RESOURCES)
    write_page("![[View/Services]]\n\nText ![[Analysis/Check]] inline.\n\n```\n![[View/Services]]\n```\n\n`![[View/Services]]`\n")
    @previous_dir = Archsight.resources_dir
    Archsight.resources_dir = @dir
    @previous_db = app.instance_variable_get(:@database)
    reload
  end

  def teardown
    Archsight.resources_dir = @previous_dir
    app.instance_variable_set(:@database, @previous_db)
    FileUtils.rm_rf(@dir)
  end

  def write_page(body)
    File.write(File.join(@dir, "p.md"), "---\ntitle: P\n---\n\n#{body}")
  end

  def reload
    app.instance_variable_set(:@database, Archsight::Database.new(@dir).tap(&:reload!))
  end

  def html_of(body)
    write_page(body)
    reload
    get "/api/v1/pages/p"

    JSON.parse(last_response.body)["html"]
  end

  def test_a_paragraph_with_only_an_embed_becomes_a_placeholder_with_a_fallback_link
    html = html_of("![[View/Services]]\n")

    assert_includes html, '<div class="kind-embed" data-kind="View" data-name="Services"><a href="/kinds/View/instances/Services">Services</a></div>'
    refute_includes html, "<p><div"
  end

  def test_an_inline_embed_degrades_to_a_link
    html = html_of("See ![[Analysis/Check]] here.\n")

    assert_includes html, '<a href="/kinds/Analysis/instances/Check">Check</a>'
    refute_includes html, "kind-embed"
  end

  def test_code_is_left_alone
    html = html_of("```\n![[View/Services]]\n```\n\n`![[View/Services]]`\n")

    refute_includes html, "kind-embed"
    assert_equal 2, html.scan("![[View/Services]]").length
  end

  def test_other_kinds_and_unknown_names_are_broken_markers
    html = html_of("![[ApplicationService/Svc]]\n\n![[View/Nope]]\n\n![[Svc]]\n")

    assert_equal 3, html.scan('class="broken-link"').length
    assert_includes html, "only View and Analysis can be embedded"
    assert_includes html, "no such resource"
    refute_includes html, "kind-embed"
  end

  def test_rendering_a_page_does_not_run_anything
    ran = false
    original = Archsight::Analysis::Executor.instance_method(:execute) if defined?(Archsight::Analysis::Executor)
    Archsight::Analysis::Executor.define_method(:execute) { |*| ran = true } if original
    html_of("![[Analysis/Check]]\n\n![[View/Services]]\n")
  ensure
    Archsight::Analysis::Executor.define_method(:execute, original) if original

    refute ran, "an embed is only a placeholder on the server"
  end

  def test_lint_reports_embeds_that_do_not_resolve
    write_page("![[View/Services]]\n![[View/Nope]]\n![[ApplicationService/Svc]]\n\n```\n![[View/InCode]]\n```\n\nand `![[View/InlineCode]]`\n")
    reload
    errors = Archsight::Linter.new(app.instance_variable_get(:@database)).validate

    assert(errors.any? { |e| e.include?("![[View/Nope]]") && e.include?("no such resource") })
    assert(errors.any? { |e| e.include?("![[ApplicationService/Svc]]") && e.include?("only View and Analysis") })
    refute(errors.any? { |e| e.include?("View/Services]]") || e.include?("InCode") || e.include?("InlineCode") })
    refute(errors.any? { |e| e.include?("links to unknown") }, "an embed is not also reported as a broken [[link]]")
  end
end
