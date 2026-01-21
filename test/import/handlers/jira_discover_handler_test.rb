# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "webmock/minitest"
require "archsight/import/handlers/jira_discover"
require "archsight/import/progress"

class JiraDiscoverHandlerTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
    @original_token = ENV.fetch("JIRA_TOKEN", nil)
    ENV["JIRA_TOKEN"] = "test-jira-token"
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
    if @original_token
      ENV["JIRA_TOKEN"] = @original_token
    else
      ENV.delete("JIRA_TOKEN")
    end
  end

  def test_missing_jira_token_raises_error
    ENV.delete("JIRA_TOKEN")
    handler = create_handler(host: "jira.example.com")

    error = assert_raises(RuntimeError) { handler.execute }
    assert_equal "Missing required environment variable: JIRA_TOKEN", error.message
  end

  def test_missing_host_config_raises_error
    handler = create_handler(host: nil)

    error = assert_raises(RuntimeError) { handler.execute }
    assert_equal "Missing required config: host", error.message
  end

  def test_authentication_failure
    stub_jira_auth_failure

    handler = create_handler(host: "jira.example.com")

    error = assert_raises(RuntimeError) { handler.execute }
    assert_includes error.message, "authentication failed"
  end

  def test_discover_projects_for_teams
    stub_jira_auth_success
    stub_user_search("alice@example.com", "alice")
    stub_user_search("bob@example.com", "bob")
    stub_issue_search_with_projects("alice", "bob", { "PROJ1" => 10, "PROJ2" => 3 })
    stub_project_info("PROJ1", "Project One", "10002")

    database = create_mock_database([
                                      create_team("Team:Alpha", nil, "alice@example.com", ["bob@example.com"])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      min_activity_threshold: "5",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Discover.yaml")

    assert_path_exists output_path

    content = File.read(output_path)

    assert_includes content, "Team:Alpha"
    assert_includes content, "team/jira"
    assert_includes content, "PROJ1"
  end

  def test_excludes_project_categories
    stub_jira_auth_success
    stub_user_search("alice@example.com", "alice")
    stub_issue_search_with_projects("alice", nil, { "EXCLUDED" => 20, "INCLUDED" => 10 })
    stub_project_info("EXCLUDED", "Excluded Project", "12003") # Excluded category
    stub_project_info("INCLUDED", "Included Project", "10002")

    database = create_mock_database([
                                      create_team("Team:Beta", nil, "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      excluded_project_categories: "12003",
      min_activity_threshold: "5",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Discover.yaml")
    content = File.read(output_path)

    assert_includes content, "INCLUDED"
    refute_includes content, "team/jira: EXCLUDED"
  end

  def test_excludes_specific_projects
    stub_jira_auth_success
    stub_user_search("alice@example.com", "alice")
    stub_issue_search_with_projects("alice", nil, { "TOPIDEA" => 20, "VALID" => 10 })
    stub_project_info("VALID", "Valid Project", "10002")

    database = create_mock_database([
                                      create_team("Team:Gamma", nil, "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      excluded_projects: "TOPIDEA,CR",
      min_activity_threshold: "5",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Discover.yaml")
    content = File.read(output_path)

    assert_includes content, "VALID"
    refute_includes content, "team/jira: TOPIDEA"
  end

  def test_respects_activity_threshold
    stub_jira_auth_success
    stub_user_search("alice@example.com", "alice")
    stub_issue_search_with_projects("alice", nil, { "LOWACT" => 3, "HIGHACT" => 10 })
    stub_project_info("HIGHACT", "High Activity Project", "10002")

    database = create_mock_database([
                                      create_team("Team:Delta", nil, "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      min_activity_threshold: "5",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Discover.yaml")
    content = File.read(output_path)

    assert_includes content, "HIGHACT"
    refute_includes content, "team/jira: LOWACT"
  end

  def test_ignores_specified_teams
    stub_jira_auth_success

    database = create_mock_database([
                                      create_team("Bot:Team", nil, "bot@example.com", []),
                                      create_team("Team:Valid", nil, "alice@example.com", [])
                                    ])

    # Only stub for valid team, ignored team shouldn't be processed
    stub_user_search("alice@example.com", "alice")
    stub_issue_search_with_projects("alice", nil, { "PROJ" => 10 })
    stub_project_info("PROJ", "Project", "10002")

    handler = create_handler(
      host: "jira.example.com",
      ignored_teams: "Bot:Team,No:Team",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Discover.yaml")
    content = File.read(output_path)

    assert_includes content, "Team:Valid"
    refute_includes content, "Bot:Team"
  end

  def test_skips_teams_with_existing_jira_project
    stub_jira_auth_success

    # Team already has team/jira set - should be skipped
    database = create_mock_database([
                                      create_team("Team:Configured", "EXISTING", "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      database: database
    )
    handler.execute

    # Handler uses safe_filename(import_resource.name) -> Import_Jira_Discover.yaml
    output_path = File.join(@resources_dir, "generated", "Import_Jira_Discover.yaml")
    content = File.read(output_path)

    # Should only have self-marker, no team patches
    refute_includes content, "Team:Configured"
    assert_includes content, "Import:Jira:Discover" # Self-marker
  end

  private

  def create_handler(host:, min_activity_threshold: "5", excluded_project_categories: nil,
                     excluded_projects: nil, ignored_teams: nil, database: nil)
    annotations = {
      "import/handler" => "jira-discover"
    }
    annotations["import/config/host"] = host if host
    annotations["import/config/minActivityThreshold"] = min_activity_threshold
    annotations["import/config/excludedProjectCategories"] = excluded_project_categories if excluded_project_categories
    annotations["import/config/excludedProjects"] = excluded_projects if excluded_projects
    annotations["import/config/ignoredTeams"] = ignored_teams if ignored_teams
    annotations["import/config/rateLimitMs"] = "0" # No rate limiting in tests

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:Jira:Discover",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockJiraImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    db = database || create_mock_database([])

    Archsight::Import::Handlers::JiraDiscover.new(
      import_resource,
      database: db,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def create_mock_database(teams)
    MockJiraDatabase.new(teams)
  end

  def create_team(name, jira_project, lead_email, member_emails)
    annotations = {}
    annotations["team/jira"] = jira_project if jira_project
    annotations["team/lead"] = lead_email if lead_email
    annotations["team/members"] = member_emails.join("\n") unless member_emails.empty?

    MockJiraTeam.new(name, annotations)
  end

  def stub_jira_auth_success
    stub_request(:get, "https://jira.example.com/rest/api/2/myself")
      .with(headers: { "Authorization" => "Bearer test-jira-token" })
      .to_return(
        status: 200,
        body: { "displayName" => "Test User", "name" => "testuser" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_jira_auth_failure
    stub_request(:get, "https://jira.example.com/rest/api/2/myself")
      .to_return(status: 401, body: "Unauthorized")
  end

  def stub_user_search(email, username)
    # Match user search endpoint with any query params
    stub_request(:get, %r{https://jira\.example\.com/rest/api/2/user/search\?})
      .to_return(
        status: 200,
        body: [{ "name" => username, "emailAddress" => email }].to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_issue_search_with_projects(_user1, _user2, project_counts)
    issues = project_counts.flat_map do |key, count|
      count.times.map do
        { "fields" => { "project" => { "key" => key } } }
      end
    end

    # Match search endpoint with any query params
    stub_request(:get, %r{https://jira\.example\.com/rest/api/2/search\?})
      .to_return(
        status: 200,
        body: { "issues" => issues }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_project_info(project_key, project_name, category_id)
    stub_request(:get, "https://jira.example.com/rest/api/2/project/#{project_key}")
      .to_return(
        status: 200,
        body: {
          "key" => project_key,
          "name" => project_name,
          "projectCategory" => { "id" => category_id, "name" => "Category" }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  # Mock classes for testing
  class MockJiraImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/jira-test.yaml")
    end
  end

  class MockJiraTeam
    attr_reader :name, :annotations

    def initialize(name, annotations)
      @name = name
      @annotations = annotations
    end
  end

  class MockJiraDatabase
    def initialize(teams)
      @teams = teams.each_with_object({}) { |t, h| h[t.name] = t }
    end

    def instances_by_kind(kind)
      return @teams if kind == "BusinessActor"

      {}
    end
  end
end
