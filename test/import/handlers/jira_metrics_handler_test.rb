# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "webmock/minitest"
require "archsight/import/handlers/jira_metrics"
require "archsight/import/progress"

class JiraMetricsHandlerTest < Minitest::Test
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

  def test_collects_metrics_for_teams_with_jira
    stub_jira_auth_success
    stub_user_search("alice@example.com", "alice")
    stub_monthly_issue_counts("PROJ1", "alice", created: [5, 8, 3, 6, 4, 7], resolved: [4, 7, 2, 5, 3, 6])

    database = create_mock_database([
                                      create_team("Team:Alpha", "PROJ1", "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      months_to_analyze: "6",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Metrics.yaml")

    assert_path_exists output_path

    content = File.read(output_path)

    assert_includes content, "Team:Alpha"
    assert_includes content, "jira/issues/created"
    assert_includes content, "jira/issues/resolved"
    assert_includes content, "5,8,3,6,4,7"
    assert_includes content, "4,7,2,5,3,6"
  end

  def test_skips_teams_without_activity
    stub_jira_auth_success
    stub_user_search("alice@example.com", "alice")
    stub_monthly_issue_counts("PROJ1", "alice", created: [0, 0, 0, 0, 0, 0], resolved: [0, 0, 0, 0, 0, 0])

    database = create_mock_database([
                                      create_team("Team:Inactive", "PROJ1", "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      months_to_analyze: "6",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Metrics.yaml")
    content = File.read(output_path)

    # Should only have self-marker, no team patches
    refute_includes content, "Team:Inactive"
  end

  def test_skips_teams_without_jira_project
    stub_jira_auth_success

    database = create_mock_database([
                                      create_team("Team:NoJira", nil, "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Metrics.yaml")
    content = File.read(output_path)

    # Should only have self-marker
    refute_includes content, "Team:NoJira"
  end

  def test_ignores_specified_teams
    stub_jira_auth_success
    stub_user_search("alice@example.com", "alice")
    stub_monthly_issue_counts("PROJ1", "alice", created: [5, 8, 3, 6, 4, 7], resolved: [4, 7, 2, 5, 3, 6])

    database = create_mock_database([
                                      create_team("Bot:Team", "BOTPROJ", "bot@example.com", []),
                                      create_team("Team:Valid", "PROJ1", "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      ignored_teams: "Bot:Team,No:Team",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Metrics.yaml")
    content = File.read(output_path)

    assert_includes content, "Team:Valid"
    refute_includes content, "Bot:Team"
  end

  def test_handles_comma_separated_jira_projects
    stub_jira_auth_success
    stub_user_search("alice@example.com", "alice")
    # Should use first project key
    stub_monthly_issue_counts("PROJ1", "alice", created: [5, 8, 3, 6, 4, 7], resolved: [4, 7, 2, 5, 3, 6])

    database = create_mock_database([
                                      create_team("Team:MultiProj", "PROJ1,PROJ2", "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      months_to_analyze: "6",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Metrics.yaml")
    content = File.read(output_path)

    assert_includes content, "Team:MultiProj"
    assert_includes content, "jira/issues/created"
  end

  def test_configurable_months_to_analyze
    stub_jira_auth_success
    stub_user_search("alice@example.com", "alice")
    stub_monthly_issue_counts("PROJ1", "alice", created: [5, 8, 3], resolved: [4, 7, 2])

    database = create_mock_database([
                                      create_team("Team:Short", "PROJ1", "alice@example.com", [])
                                    ])

    handler = create_handler(
      host: "jira.example.com",
      months_to_analyze: "3",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Metrics.yaml")
    content = File.read(output_path)

    assert_includes content, "5,8,3"
    assert_includes content, "4,7,2"
  end

  def test_output_includes_self_marker
    stub_jira_auth_success

    database = create_mock_database([])

    handler = create_handler(
      host: "jira.example.com",
      database: database
    )
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_Jira_Metrics.yaml")
    content = File.read(output_path)

    assert_includes content, "Import:Jira:Metrics"
    assert_includes content, "generated/at"
  end

  private

  def create_handler(host:, months_to_analyze: "6", ignored_teams: nil, database: nil)
    annotations = {
      "import/handler" => "jira-metrics"
    }
    annotations["import/config/host"] = host if host
    annotations["import/config/monthsToAnalyze"] = months_to_analyze
    annotations["import/config/ignoredTeams"] = ignored_teams if ignored_teams
    annotations["import/config/rateLimitMs"] = "0" # No rate limiting in tests

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:Jira:Metrics",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockJiraMetricsImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    db = database || create_mock_database([])

    Archsight::Import::Handlers::JiraMetrics.new(
      import_resource,
      database: db,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def create_mock_database(teams)
    MockJiraMetricsDatabase.new(teams)
  end

  def create_team(name, jira_project, lead_email, member_emails)
    annotations = {}
    annotations["team/jira"] = jira_project if jira_project
    annotations["team/lead"] = lead_email if lead_email
    annotations["team/members"] = member_emails.join("\n") unless member_emails.empty?

    MockJiraMetricsTeam.new(name, annotations)
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

  def stub_monthly_issue_counts(_project_key, _username, created:, resolved:)
    # Create a combined array to return counts in order
    # WebMock returns responses in sequence when multiple requests match
    counts = []
    created.size.times do |i|
      counts << created[i]
      counts << resolved[i]
    end

    # Stub search endpoint with any query params - returns counts in sequence
    stub_request(:get, %r{https://jira\.example\.com/rest/api/2/search\?})
      .to_return(*counts.map { |c| { status: 200, body: { "total" => c }.to_json, headers: { "Content-Type" => "application/json" } } })
  end

  # Mock classes for testing
  class MockJiraMetricsImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/jira-test.yaml")
    end
  end

  class MockJiraMetricsTeam
    attr_reader :name, :annotations

    def initialize(name, annotations)
      @name = name
      @annotations = annotations
    end
  end

  class MockJiraMetricsDatabase
    def initialize(teams)
      @teams = teams.each_with_object({}) { |t, h| h[t.name] = t }
    end

    def instances_by_kind(kind)
      return @teams if kind == "BusinessActor"

      {}
    end
  end
end
