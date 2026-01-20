# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "webmock/minitest"
require "archsight/import/handlers/github"
require "archsight/import/progress"

class GithubHandlerTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
    @original_token = ENV.fetch("GITHUB_TOKEN", nil)
    ENV["GITHUB_TOKEN"] = "test-token"
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
    if @original_token
      ENV["GITHUB_TOKEN"] = @original_token
    else
      ENV.delete("GITHUB_TOKEN")
    end
  end

  def test_missing_github_token_raises_error
    ENV.delete("GITHUB_TOKEN")
    handler = create_handler(org: "test-org")

    error = assert_raises(RuntimeError) { handler.execute }
    assert_equal "Missing required environment variable: GITHUB_TOKEN", error.message
  end

  def test_missing_org_config_raises_error
    handler = create_handler(org: nil)

    error = assert_raises(RuntimeError) { handler.execute }
    assert_equal "Missing required config: org", error.message
  end

  def test_fetch_repos_transforms_response
    stub_request(:get, "https://api.github.com/orgs/test-org/repos?page=1&per_page=100")
      .with(headers: {
              "Accept" => "application/vnd.github+json",
              "Authorization" => "Bearer test-token",
              "X-Github-Api-Version" => "2022-11-28"
            })
      .to_return(
        status: 200,
        body: [
          {
            "name" => "repo1",
            "archived" => false,
            "visibility" => "public",
            "ssh_url" => "git@github.com:test-org/repo1.git",
            "html_url" => "https://github.com/test-org/repo1"
          }
        ].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    handler = create_handler(org: "test-org", repo_output_path: "generated/repos.yaml")
    handler.execute

    # Check that output file was written (uses safe_filename on import name)
    output_path = File.join(@resources_dir, "generated", "Import_GitHub.yaml")

    assert_path_exists output_path

    content = File.read(output_path)

    assert_includes content, "Import:Repo:github:test-org:repo1"
    assert_includes content, "git@github.com:test-org/repo1.git"
  end

  def test_unauthorized_error_handling
    stub_request(:get, "https://api.github.com/orgs/test-org/repos?page=1&per_page=100")
      .to_return(status: 401, body: "Unauthorized")

    handler = create_handler(org: "test-org")

    error = assert_raises(RuntimeError) { handler.execute }
    assert_includes error.message, "401 Unauthorized"
  end

  def test_forbidden_error_handling
    stub_request(:get, "https://api.github.com/orgs/test-org/repos?page=1&per_page=100")
      .to_return(status: 403, body: "Forbidden")

    handler = create_handler(org: "test-org")

    error = assert_raises(RuntimeError) { handler.execute }
    assert_includes error.message, "403 Forbidden"
  end

  def test_rate_limit_error_handling
    stub_request(:get, "https://api.github.com/orgs/test-org/repos?page=1&per_page=100")
      .to_return(
        status: 403,
        body: "Rate limit exceeded",
        headers: {
          "X-RateLimit-Remaining" => "0",
          "X-RateLimit-Reset" => (Time.now.to_i + 3600).to_s
        }
      )

    handler = create_handler(org: "test-org")

    error = assert_raises(RuntimeError) { handler.execute }
    assert_includes error.message, "Rate limit exceeded"
  end

  def test_not_found_error_handling
    stub_request(:get, "https://api.github.com/orgs/nonexistent-org/repos?page=1&per_page=100")
      .to_return(status: 404, body: "Not Found")

    handler = create_handler(org: "nonexistent-org")

    error = assert_raises(RuntimeError) { handler.execute }
    assert_includes error.message, "404 Not Found"
    assert_includes error.message, "nonexistent-org"
  end

  private

  def create_handler(org:, repo_output_path: nil)
    annotations = {
      "import/handler" => "github"
    }
    annotations["import/config/org"] = org if org
    annotations["import/config/repoOutputPath"] = repo_output_path if repo_output_path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:GitHub",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockGithubImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::Github.new(import_resource, database: nil, resources_dir: @resources_dir,
                                                             progress: progress)
  end

  # Mock import resource for testing
  class MockGithubImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/github-test.yaml")
    end
  end
end
