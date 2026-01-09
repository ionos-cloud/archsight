# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "json"
require "uri"

class HelpersTest < Minitest::Test
  include Archsight::Helpers

  # classify tests

  def test_classify_simple
    assert_equal "Hello", classify("hello")
  end

  def test_classify_with_dashes
    assert_equal "HelloWorld", classify("hello-world")
  end

  def test_classify_multiple_dashes
    assert_equal "OneTwoThree", classify("one-two-three")
  end

  # deep_merge tests

  def test_deep_merge_simple
    h1 = { a: 1, b: 2 }
    h2 = { b: 3, c: 4 }
    result = deep_merge(h1, h2)

    assert_equal({ a: 1, b: 3, c: 4 }, result)
  end

  def test_deep_merge_nested_hashes
    h1 = { a: { x: 1, y: 2 } }
    h2 = { a: { y: 3, z: 4 } }
    result = deep_merge(h1, h2)

    assert_equal({ a: { x: 1, y: 3, z: 4 } }, result)
  end

  def test_deep_merge_arrays
    h1 = { a: [1, 2] }
    h2 = { a: [2, 3] }
    result = deep_merge(h1, h2)

    assert_equal({ a: [1, 2, 3] }, result)
  end

  def test_deep_merge_does_not_mutate_original
    h1 = { a: 1 }
    h2 = { b: 2 }
    deep_merge(h1, h2)

    assert_equal({ a: 1 }, h1)
  end

  # icon_for_url tests

  def test_icon_for_github
    assert_equal "iconoir-github", icon_for_url("https://github.com/owner/repo")
  end

  def test_icon_for_gitlab
    assert_equal "iconoir-git-fork", icon_for_url("https://gitlab.com/owner/repo")
  end

  def test_icon_for_google_docs
    assert_equal "iconoir-google-docs", icon_for_url("https://docs.google.com/document/d/123")
  end

  def test_icon_for_confluence
    assert_equal "iconoir-page-edit", icon_for_url("https://company.confluence.com/page")
  end

  def test_icon_for_jira
    assert_equal "iconoir-list", icon_for_url("https://jira.company.com/browse/PROJ-123")
  end

  def test_icon_for_grafana
    assert_equal "iconoir-graph-up", icon_for_url("https://grafana.company.com/dashboard")
  end

  def test_icon_for_prometheus
    assert_equal "iconoir-database", icon_for_url("https://prometheus.company.com")
  end

  def test_icon_for_api
    assert_equal "iconoir-code", icon_for_url("https://api.company.com/v1")
  end

  def test_icon_for_docs
    assert_equal "iconoir-book", icon_for_url("https://docs.company.com/guide")
  end

  def test_icon_for_unknown
    assert_equal "iconoir-internet", icon_for_url("https://example.com")
  end

  # category_for_url tests

  def test_category_for_github
    assert_equal "Code Repository", category_for_url("https://github.com/owner/repo")
  end

  def test_category_for_confluence
    assert_equal "Documentation", category_for_url("https://confluence.company.com")
  end

  def test_category_for_jira
    assert_equal "Project Management", category_for_url("https://jira.company.com")
  end

  def test_category_for_grafana
    assert_equal "Monitoring", category_for_url("https://grafana.company.com")
  end

  def test_category_for_unknown
    assert_equal "Other", category_for_url("https://example.com")
  end

  # github_raw_base_url tests

  def test_github_raw_base_url_ssh
    result = github_raw_base_url("git@github.com:owner/repo.git")

    assert_equal "https://raw.githubusercontent.com/owner/repo/main", result
  end

  def test_github_raw_base_url_https
    result = github_raw_base_url("https://github.com/owner/repo")

    assert_equal "https://raw.githubusercontent.com/owner/repo/main", result
  end

  def test_github_raw_base_url_custom_branch
    result = github_raw_base_url("https://github.com/owner/repo", branch: "develop")

    assert_equal "https://raw.githubusercontent.com/owner/repo/develop", result
  end

  def test_github_raw_base_url_nil
    assert_nil github_raw_base_url(nil)
  end

  def test_github_raw_base_url_non_github
    assert_nil github_raw_base_url("https://gitlab.com/owner/repo")
  end

  # resolve_relative_urls tests

  def test_resolve_relative_urls_simple
    content = '<img src="image.png">'
    result = resolve_relative_urls(content, "https://example.com")

    assert_equal '<img src="https://example.com/image.png">', result
  end

  def test_resolve_relative_urls_dot_slash
    content = '<img src="./image.png">'
    result = resolve_relative_urls(content, "https://example.com")

    assert_equal '<img src="https://example.com/image.png">', result
  end

  def test_resolve_relative_urls_absolute_unchanged
    content = '<img src="https://other.com/image.png">'
    result = resolve_relative_urls(content, "https://example.com")

    assert_equal '<img src="https://other.com/image.png">', result
  end

  def test_resolve_relative_urls_nil_base
    content = '<img src="image.png">'
    result = resolve_relative_urls(content, nil)

    assert_equal '<img src="image.png">', result
  end

  # compare_values tests

  def test_compare_values_integers
    assert_equal(-1, compare_values("1", "10"))
    assert_equal 0, compare_values("5", "5")
    assert_equal 1, compare_values("10", "1")
  end

  def test_compare_values_strings
    assert_equal(-1, compare_values("apple", "banana"))
    assert_equal 0, compare_values("apple", "Apple")
    assert_equal 1, compare_values("banana", "apple")
  end

  def test_compare_values_nil_handling
    assert_equal(-1, compare_values(nil, "a"))
    assert_equal 1, compare_values("a", nil)
    assert_equal 0, compare_values(nil, nil)
  end

  # sort_instances tests

  def test_sort_instances_empty_fields
    instances = [mock_instance("B"), mock_instance("A")]
    result = sort_instances(instances, [])

    assert_equal %w[B A], result.map(&:name)
  end

  def test_sort_instances_by_name
    instances = [mock_instance("B"), mock_instance("A"), mock_instance("C")]
    result = sort_instances(instances, ["name"])

    assert_equal %w[A B C], result.map(&:name)
  end

  def test_sort_instances_by_name_descending
    instances = [mock_instance("B"), mock_instance("A"), mock_instance("C")]
    result = sort_instances(instances, ["-name"])

    assert_equal %w[C B A], result.map(&:name)
  end

  # relative_error_path tests

  def test_relative_error_path_with_resources
    path = "/home/user/project/resources/teams/backend.yaml"

    assert_equal "resources/teams/backend.yaml", relative_error_path(path)
  end

  def test_relative_error_path_without_resources
    path = "/home/user/project/config/settings.yaml"

    assert_equal "settings.yaml", relative_error_path(path)
  end

  # error_context_lines tests

  def test_error_context_lines_returns_context
    content = "line1\nline2\nline3\nline4\nline5\n"

    Tempfile.create(["test", ".yaml"]) do |f|
      f.write(content)
      f.flush

      result = error_context_lines(f.path, 3, context_lines: 1)

      assert_kind_of Array, result
      assert(result.any? { |line| line[:selected] })
    end
  end

  def test_error_context_lines_nonexistent_file
    result = error_context_lines("/nonexistent/file.yaml", 1)

    assert_empty result
  end

  # search_link_attrs tests

  def test_search_link_attrs
    attrs = search_link_attrs("status == active")

    assert attrs.key?("href")
    assert attrs.key?("hx-post")
    assert attrs.key?("hx-target")
  end

  # filter_link_attrs tests

  def test_filter_link_attrs
    attrs = filter_link_attrs("status", "active")

    assert attrs.key?("href")
  end

  def test_filter_link_attrs_with_kind
    attrs = filter_link_attrs("status", "active", "==", "TechnologyArtifact")

    assert attrs.key?("href")
    assert_includes attrs["href"], "TechnologyArtifact"
  end

  def test_filter_link_attrs_with_custom_method
    attrs = filter_link_attrs("count", "10", ">")

    assert attrs.key?("href")
    assert_includes attrs["href"], "%3E" # URL encoded >
  end

  # More sort_instances tests

  def test_sort_instances_by_kind
    instances = [mock_instance("A", {}, "Zebra"), mock_instance("B", {}, "Apple")]
    result = sort_instances(instances, ["kind"])

    assert_equal %w[B A], result.map(&:name)
  end

  def test_sort_instances_by_annotation
    instances = [
      mock_instance("A", { "priority" => "low" }),
      mock_instance("B", { "priority" => "high" })
    ]
    result = sort_instances(instances, ["priority"])

    assert_equal %w[B A], result.map(&:name)
  end

  def test_sort_instances_by_numeric_annotation
    instances = [
      mock_instance("A", { "count" => "10" }),
      mock_instance("B", { "count" => "2" })
    ]
    result = sort_instances(instances, ["count"])

    assert_equal %w[B A], result.map(&:name)
  end

  # More error_context_lines tests

  def test_error_context_lines_with_yaml_document
    content = "---\nname: test\nvalue: 1\n---\nname: other\n"

    Tempfile.create(["test", ".yaml"]) do |f|
      f.write(content)
      f.flush

      result = error_context_lines(f.path, 2, context_lines: 1)

      assert_kind_of Array, result
      selected = result.find { |line| line[:selected] }

      assert_equal 2, selected[:line_no]
    end
  end

  # category_for_url tests - additional cases

  def test_category_for_google_docs
    assert_equal "Documentation", category_for_url("https://docs.google.com/document/d/123")
  end

  def test_category_for_prometheus
    assert_equal "Monitoring", category_for_url("https://prometheus.company.com")
  end

  def test_category_for_api
    assert_equal "API", category_for_url("https://api.company.com/v1")
  end

  def test_category_for_docs
    assert_equal "Documentation", category_for_url("https://docs.company.com/guide")
  end

  private

  def mock_instance(name, annotations = {}, klass = "Test")
    Struct.new(:name, :klass, :annotations).new(name, klass, annotations)
  end
end
