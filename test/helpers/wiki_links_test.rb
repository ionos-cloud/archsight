# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/helpers"

class WikiLinksTest < Minitest::Test
  DATA = <<~YAML.freeze
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: KubeVirt
      annotations:
        architecture/description: |
          **KubeVirt** runs [virtual machines](https://example.com) on `Kubernetes` with [[ApplicationComponent/CAPI|CAPI]] & <b>more</b>.

          Second paragraph.
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: CAPI
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: CAPI
      annotations:
        architecture/description: #{"x" * 300}
  YAML

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "data.yaml"), DATA)
    File.write(File.join(@dir, "ready.md"), "---\ntitle: Ready Page\nstatus: approved\n---\n\nx\n")
    @db = Archsight::Database.new(@dir, compute_annotations: false).tap(&:reload!)
    @wiki = Archsight::Helpers::WikiLinks.new(@db)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def render(text) = @wiki.render(text)

  def test_a_kind_name_link_shows_the_name_only_and_the_kind_with_the_description_on_hover
    html = render("[[ApplicationComponent/KubeVirt]]")

    assert_includes html, %(<a href="/kinds/ApplicationComponent/instances/KubeVirt" title="ApplicationComponent\n)
    assert_includes html, ">KubeVirt</a>"
    refute_includes html, ">ApplicationComponent/KubeVirt<"
  end

  def test_the_hover_text_is_the_first_line_as_plain_text_and_escaped
    html = render("[[ApplicationComponent/KubeVirt]]")

    assert_includes html, "title=\"ApplicationComponent\nKubeVirt runs virtual machines on Kubernetes with CAPI &amp; &lt;b&gt;more&lt;/b&gt;.\""
  end

  def test_a_long_description_is_cut
    title = render("[[ApplicationService/CAPI]]")[/title="([^"]*)"/, 1]

    assert_equal "ApplicationService", title.lines.first.strip
    assert_equal 200, title.lines.last.length
    assert title.end_with?("…"), "cut text ends with an ellipsis"
  end

  def test_a_resource_without_a_description_has_the_kind_only
    assert_includes render("[[ApplicationComponent/CAPI]]"), 'title="ApplicationComponent">CAPI</a>'
  end

  def test_a_page_is_shown_by_title_with_its_status_on_hover
    html = render("[[ready]] [[Ready Page]]")

    assert_equal 2, html.scan(%(<a href="/pages/ready" title="Page\napproved">Ready Page</a>)).length
  end

  def test_explicit_labels_bare_names_and_broken_references_are_unchanged
    html = render("[[ApplicationComponent/KubeVirt|the VM]] [[KubeVirt]] [[ApplicationComponent/Nope]] [[CAPI]]")

    assert_includes html, ">the VM</a>"
    assert_includes html, ">KubeVirt</a>"
    assert_includes html, '<span class="broken-link" title="Resource not found">ApplicationComponent/Nope</span>'
    assert_includes html, '<span class="broken-link" title="Ambiguous reference">CAPI</span>'
  end

  def test_label_and_target_for
    assert_equal "KubeVirt", @wiki.label_for("ApplicationComponent/KubeVirt")
    assert_equal "Ready Page", @wiki.label_for("ready")
    assert_equal "ApplicationComponent/Nope", @wiki.label_for("ApplicationComponent/Nope")
    assert_equal "ApplicationComponent", @wiki.target_for("ApplicationComponent/KubeVirt").class.name.split("::").last
    assert_nil @wiki.target_for("CAPI")
    assert_nil @wiki.target_for("Nope")
  end
end
