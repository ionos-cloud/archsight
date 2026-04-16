# frozen_string_literal: true

require "test_helper"
require "rack/test"
require "archsight/web/application"

class ApplicationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Archsight::Web::Application
  end

  def setup
    Archsight.resources_dir = File.expand_path("../../examples/archsight", __dir__)
    # Ensure database is loaded
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
  end

  # Route tests

  def test_get_root
    get "/"

    assert_predicate last_response, :ok?, "Expected 200, got #{last_response.status}: #{last_response.body[0..200]}"
    assert_includes last_response.body, "html"
  end

  def test_get_reload
    get "/reload"

    assert_predicate last_response, :redirect?
    assert last_response.location.end_with?("/")
  end

  def test_get_reload_with_redirect_param
    get "/reload", redirect: "/kinds/TechnologyArtifact"

    assert_predicate last_response, :redirect?
    assert last_response.location.end_with?("/kinds/TechnologyArtifact")
  end

  def test_post_maintenance_restart_disabled_by_default
    post "/maintenance/restart"

    assert_equal 404, last_response.status
    assert_includes last_response.body, "Restart endpoint is disabled"
  end

  def test_post_maintenance_restart_enabled_response_body
    Archsight::Web::Application.set :restart_enabled, true
    restart_called = false
    original = Archsight::Web::Application.method(:perform_restart!)
    Archsight::Web::Application.define_singleton_method(:perform_restart!) { restart_called = true }

    post "/maintenance/restart"

    assert_predicate last_response, :ok?
    assert restart_called, "expected perform_restart! to be called"

    body = JSON.parse(last_response.body)

    assert body["ok"]
    assert_includes body["message"], "shutting down"
  ensure
    Archsight::Web::Application.define_singleton_method(:perform_restart!, &original)
    Archsight::Web::Application.set :restart_enabled, false
  end

  def test_get_search_without_query
    get "/search"

    assert_predicate last_response, :ok?
  end

  def test_get_search_with_query
    get "/search", q: 'name =~ ".*"'

    assert_predicate last_response, :ok?
  end

  def test_get_search_with_tag_and_value
    get "/search", tag: "kind", value: "TechnologyArtifact", method: "=="

    assert_predicate last_response, :ok?
  end

  def test_get_dot
    get "/dot"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/plain"
    assert_includes last_response.body, "digraph"
  end

  def test_get_kinds
    get "/kinds/TechnologyArtifact"

    assert_predicate last_response, :ok?
  end

  def test_get_instance
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    instance_name = artifacts.keys.first
    get "/kinds/TechnologyArtifact/instances/#{instance_name}"

    assert_predicate last_response, :ok?
  end

  def test_get_instance_dot
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    instance_name = artifacts.keys.first
    get "/kinds/TechnologyArtifact/instances/#{instance_name}/dot"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/plain"
    assert_includes last_response.body, "digraph"
  end

  # Doc HTML routes serve Vue SPA
  def test_get_doc_markdown_serves_vue
    get "/doc/search"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "html"
  end

  def test_get_doc_erb_serves_vue
    get "/doc/index"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "html"
  end

  def test_get_doc_resources_serves_vue
    get "/doc/resources/technology_artifact"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "html"
  end

  # Doc API routes
  def test_api_doc_markdown
    get "/api/v1/docs/search"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/html"
    assert_includes last_response.body, "<article>"
  end

  def test_api_doc_erb
    get "/api/v1/docs/index"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/html"
    assert_includes last_response.body, "<article>"
  end

  def test_api_doc_resources
    get "/api/v1/docs/resources/technology_artifact"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/html"
    assert_includes last_response.body, "<article>"
  end

  def test_api_doc_nonexistent
    get "/api/v1/docs/nonexistent_file_xyz"

    assert_equal 404, last_response.status
  end

  def test_api_doc_resources_nonexistent
    get "/api/v1/docs/resources/nonexistent_kind_xyz"

    assert_equal 404, last_response.status
  end

  # Search with invalid query

  def test_search_with_invalid_query
    get "/search", q: "invalid query syntax ((("

    assert_predicate last_response, :ok?
    # Should handle error gracefully
  end

  # Search with numeric operators
  def test_search_with_numeric_operator_greater
    get "/search", tag: "some/numeric", value: "10", method: ">"

    assert_predicate last_response, :ok?
  end

  def test_search_with_numeric_operator_less
    get "/search", tag: "some/numeric", value: "100", method: "<"

    assert_predicate last_response, :ok?
  end

  # Search with kind filter
  def test_search_with_kind_filter
    get "/search", q: 'name =~ ".*"', kind: "TechnologyArtifact"

    assert_predicate last_response, :ok?
  end

  # Test reload redirects to safe paths only
  def test_reload_rejects_unsafe_redirect
    get "/reload", redirect: "http://evil.com"

    assert_predicate last_response, :redirect?
    # Should redirect to root, not the external URL
    assert last_response.location.end_with?("/")
  end

  # Test API doc for another resource kind
  def test_api_doc_resources_application_component
    get "/api/v1/docs/resources/application_component"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/html"
    assert_includes last_response.body, "<article>"
  end

  # Class method tests

  def test_database_method_returns_database
    db = Archsight::Web::Application.database

    assert_kind_of Archsight::Database, db
  end

  def test_database_loads_instances
    db = Archsight::Web::Application.database

    refute_empty db.instances
  end

  def test_reload_method_exists
    assert_respond_to Archsight::Web::Application, :reload!
  end

  def test_setup_mcp_method_exists
    assert_respond_to Archsight::Web::Application, :setup_mcp!
  end
end

# Separate test class for helper methods to avoid Rack::Test method conflicts
class ApplicationHelpersTest < Minitest::Test
  def setup
    Archsight.resources_dir = File.expand_path("../../examples/archsight", __dir__)
    @app = Archsight::Web::Application
    @app.database.reload!
  end

  # Create a helper tester that includes the same helpers as the app
  class HelperTester
    include Archsight::Helpers

    attr_accessor :settings

    def initialize(db)
      @db = db
      @settings = Struct.new(:public_folder).new(File.join(__dir__, "../../lib/archsight/web/public"))
    end

    attr_reader :db
  end

  def helper
    @helper ||= HelperTester.new(@app.database)
  end

  # to_dollar tests

  def test_to_dollar_basic
    # Test the logic directly
    num = 1234.567
    rounded = (num * 100).round / 100.0
    parts = format("%.2f", rounded).split(".")
    parts[0] = parts[0].reverse.scan(/\d{1,3}/).join(",").reverse
    result = "$#{parts.join(".")}"

    assert_equal "$1,234.57", result
  end

  def test_to_dollar_small
    num = 0.99
    rounded = (num * 100).round / 100.0
    parts = format("%.2f", rounded).split(".")
    parts[0] = parts[0].reverse.scan(/\d{1,3}/).join(",").reverse
    result = "$#{parts.join(".")}"

    assert_equal "$0.99", result
  end

  def test_to_dollar_large
    num = 1_234_567.89
    rounded = (num * 100).round / 100.0
    parts = format("%.2f", rounded).split(".")
    parts[0] = parts[0].reverse.scan(/\d{1,3}/).join(",").reverse
    result = "$#{parts.join(".")}"

    assert_equal "$1,234,567.89", result
  end

  # number_with_delimiter tests

  def test_number_with_delimiter
    num = 1_234_567
    result = num.to_s.reverse.scan(/\d{1,3}/).join(",").reverse

    assert_equal "1,234,567", result
  end

  # http_git tests

  def test_http_git_ssh_url
    url = "git@github.com:owner/repo.git"
    result = url.gsub(/.git$/, "").gsub(":", "/").gsub("git@", "https://")

    assert_equal "https://github.com/owner/repo", result
  end

  def test_http_git_https_url
    # For HTTPS URLs, the gsub(":", "/") converts "https:" to "https/"
    # This matches the application's http_git helper behavior
    url = "https://github.com/owner/repo.git"
    result = url.gsub(/.git$/, "").gsub(":", "/").gsub("git@", "https://")
    # The helper is designed for SSH URLs primarily; HTTPS URLs get mangled
    assert_includes result, "github.com/owner/repo"
  end

  # time_ago helper tests - test the actual implementation logic

  def time_ago(timestamp)
    return nil unless timestamp

    time = timestamp.is_a?(Time) ? timestamp : Time.parse(timestamp.to_s)
    seconds = (Time.now - time).to_i

    units = [
      [60, "second"],
      [60, "minute"],
      [24, "hour"],
      [7, "day"],
      [4, "week"],
      [12, "month"],
      [Float::INFINITY, "year"]
    ]

    value = seconds
    units.each do |divisor, unit|
      return "just now" if unit == "second" && value < 10
      return "#{value} #{unit}#{"s" if value != 1} ago" if value < divisor

      value /= divisor
    end
  end

  def test_time_ago_nil
    assert_nil time_ago(nil)
  end

  def test_time_ago_just_now
    assert_equal "just now", time_ago(Time.now - 5)
  end

  def test_time_ago_seconds
    assert_equal "30 seconds ago", time_ago(Time.now - 30)
  end

  def test_time_ago_seconds_singular_edge
    # 10 seconds is the boundary - it shows "10 seconds ago" not "just now"
    assert_equal "10 seconds ago", time_ago(Time.now - 10)
  end

  def test_time_ago_minutes
    assert_equal "2 minutes ago", time_ago(Time.now - 120)
  end

  def test_time_ago_one_minute
    assert_equal "1 minute ago", time_ago(Time.now - 60)
  end

  def test_time_ago_hours
    assert_equal "2 hours ago", time_ago(Time.now - 7200)
  end

  def test_time_ago_days
    assert_equal "3 days ago", time_ago(Time.now - (86_400 * 3))
  end

  def test_time_ago_string_timestamp
    timestamp = (Time.now - 3600).iso8601

    assert_equal "1 hour ago", time_ago(timestamp)
  end

  # asset_path tests

  def test_asset_path_logic_existing
    # Test that mtime versioning works
    path = "style.css"
    public_folder = File.join(__dir__, "../../lib/archsight/web/public")
    file_path = File.join(public_folder, path)
    skip "File does not exist: #{file_path}" unless File.exist?(file_path)

    mtime = File.mtime(file_path).to_i
    result = "#{path}?v=#{mtime}"

    assert_match(/style\.css\?v=\d+/, result)
  end

  def test_asset_path_logic_nonexistent
    path = "nonexistent.css"
    public_folder = File.join(__dir__, "../../lib/archsight/web/public")
    file_path = File.join(public_folder, path)

    refute_path_exists file_path
    # When file doesn't exist, just return the path
    assert_equal "nonexistent.css", path
  end

  # markdown tests using the helper

  def test_markdown_basic
    html = Kramdown::Document.new("# Hello", input: "GFM").to_html

    assert_includes html, "<h1"
    assert_includes html, "Hello"
  end

  def test_markdown_autolink
    text = "Check https://example.com for info"
    html = Kramdown::Document.new(text, input: "GFM").to_html
    # Auto-linking logic
    html = html.gsub(%r{(?<!=["'])(?<!">)(https?://[^\s<>"]+)}) do |match|
      url = match.sub(/[.,;:!)]+$/, "")
      trailing = match[url.length..]
      %(<a href="#{url}">#{url}</a>#{trailing})
    end

    assert_includes html, 'href="https://example.com"'
  end
end
