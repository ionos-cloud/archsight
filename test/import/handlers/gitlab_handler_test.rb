# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "webmock/minitest"
require "archsight/import/handlers/gitlab"
require "archsight/import/progress"

class GitlabHandlerTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
    @original_token = ENV.fetch("GITLAB_TOKEN", nil)
    ENV["GITLAB_TOKEN"] = "test-token"
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
    if @original_token
      ENV["GITLAB_TOKEN"] = @original_token
    else
      ENV.delete("GITLAB_TOKEN")
    end
  end

  def test_propagates_team_config_to_child_imports
    stub_groups_request
    stub_projects_request

    handler = create_handler(
      host: "gitlab.example.com",
      fallback_team: "Team:Platform",
      bot_team: "Team:Bots",
      corporate_affixes: "ionos,1and1"
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_GitLab.yaml")

    assert_path_exists output_path

    content = File.read(output_path)

    assert_includes content, "import/config/fallbackTeam: Team:Platform"
    assert_includes content, "import/config/botTeam: Team:Bots"
    assert_includes content, "import/config/corporateAffixes: ionos,1and1"
  end

  def test_omits_team_config_when_not_set
    stub_groups_request
    stub_projects_request

    handler = create_handler(host: "gitlab.example.com")
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_GitLab.yaml")

    assert_path_exists output_path

    content = File.read(output_path)

    refute_includes content, "fallbackTeam"
    refute_includes content, "botTeam"
    refute_includes content, "corporateAffixes"
  end

  private

  def stub_groups_request
    stub_request(:get, "https://gitlab.example.com/api/v4/groups?page=1&per_page=100")
      .with(headers: { "PRIVATE-TOKEN" => "test-token" })
      .to_return(
        status: 200,
        body: [{ "id" => 1, "full_path" => "my-group" }].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Empty page 2 to stop pagination
    stub_request(:get, "https://gitlab.example.com/api/v4/groups?page=2&per_page=100")
      .with(headers: { "PRIVATE-TOKEN" => "test-token" })
      .to_return(
        status: 200,
        body: [].to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_projects_request
    stub_request(:get, %r{gitlab\.example\.com/api/v4/groups/1/projects.*page=1})
      .with(headers: { "PRIVATE-TOKEN" => "test-token" })
      .to_return(
        status: 200,
        body: [
          {
            "id" => 42,
            "path_with_namespace" => "my-group/my-service",
            "archived" => false,
            "visibility" => "internal",
            "ssh_url_to_repo" => "git@gitlab.example.com:my-group/my-service.git"
          }
        ].to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # Empty page 2 to stop pagination
    stub_request(:get, %r{gitlab\.example\.com/api/v4/groups/1/projects.*page=2})
      .with(headers: { "PRIVATE-TOKEN" => "test-token" })
      .to_return(
        status: 200,
        body: [].to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def create_handler(host:, fallback_team: nil, bot_team: nil, corporate_affixes: nil)
    annotations = {
      "import/handler" => "gitlab",
      "import/config/host" => host
    }
    annotations["import/config/fallbackTeam"] = fallback_team if fallback_team
    annotations["import/config/botTeam"] = bot_team if bot_team
    annotations["import/config/corporateAffixes"] = corporate_affixes if corporate_affixes

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:GitLab",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockGitlabImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::Gitlab.new(import_resource, database: nil, resources_dir: @resources_dir,
                                                             progress: progress)
  end

  # Mock import resource for testing
  class MockGitlabImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/gitlab-test.yaml")
    end
  end
end
