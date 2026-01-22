# frozen_string_literal: true

require "date"
require_relative "../handler"
require_relative "../registry"
require_relative "jira_base"

# Jira Metrics handler - exports per-month issue metrics for teams with team/jira set
#
# Configuration:
#   import/config/host - Jira host (required, e.g., "hosting-jira.1and1.org")
#   import/config/monthsToAnalyze - Number of months for metrics (default: 6)
#   import/config/ignoredTeams - Comma-separated team names to skip
#   import/config/rateLimitMs - API rate limit delay (default: 100)
#
# Environment:
#   JIRA_TOKEN - Jira Personal Access Token (required)
#
# Output:
#   BusinessActor patches with jira/issues/created, jira/issues/resolved annotations
class Archsight::Import::Handlers::JiraMetrics < Archsight::Import::Handler
  include Archsight::Import::Handlers::JiraBase

  def execute
    load_configuration
    verify_jira_credentials
    export_metrics

    write_generates_meta
  end

  private

  def load_configuration
    @host = config("host")
    raise "Missing required config: host" unless @host

    @token = ENV.fetch("JIRA_TOKEN", nil)
    raise "Missing required environment variable: JIRA_TOKEN" unless @token

    @months_to_analyze = config("monthsToAnalyze", default: "6").to_i
    @ignored_teams = parse_list_config(config("ignoredTeams"))
    @rate_limit_ms = config("rateLimitMs", default: "100").to_i

    init_jira_client(host: @host, token: @token, rate_limit_ms: @rate_limit_ms)
  end

  def export_metrics
    teams = load_teams(ignored_teams: @ignored_teams, require_jira: true)

    if teams.empty?
      progress.warn("No teams found with Jira project configured")
      write_yaml(YAML.dump(self_marker))
      return
    end

    progress.update("Found #{teams.size} teams with Jira project configured")
    progress.update("Collecting metrics for the last #{@months_to_analyze} months...")

    documents = teams.each_with_index.filter_map do |team, idx|
      process_team_metrics(team, idx, teams.size)
    end

    write_metrics_output(documents, teams.size)
  end

  def process_team_metrics(team, idx, total)
    project_key = team.annotations["team/jira"]
    primary_key = project_key.split(/[,\n]/).first&.strip
    emails = extract_team_emails(team)

    progress.update("[#{idx + 1}/#{total}] #{team.name} (#{primary_key})...")

    metrics = collect_team_metrics(primary_key, emails)

    if metrics[:created].all?(&:zero?) && metrics[:resolved].all?(&:zero?)
      progress.update("[#{idx + 1}/#{total}] #{team.name} (#{primary_key}) - no activity")
      return nil
    end

    log_metrics_summary(team, idx, total, metrics)
    build_metrics_document(team, metrics)
  end

  def log_metrics_summary(team, idx, total, metrics)
    created_total = metrics[:created].sum
    resolved_total = metrics[:resolved].sum
    progress.update("[#{idx + 1}/#{total}] #{team.name} - #{created_total} created, #{resolved_total} resolved")
  end

  def build_metrics_document(team, metrics)
    {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "BusinessActor",
      "metadata" => {
        "name" => team.name,
        "annotations" => {
          "jira/issues/created" => metrics[:created].join(","),
          "jira/issues/resolved" => metrics[:resolved].join(","),
          "generated/script" => import_resource.name,
          "generated/at" => Time.now.utc.iso8601
        }
      }
    }
  end

  def write_metrics_output(documents, teams_size)
    documents << self_marker

    if documents.size > 1
      yaml_content = documents.map { |doc| YAML.dump(doc) }.join("\n")
      write_yaml(yaml_content)
      progress.complete("Collected metrics for #{documents.size - 1} teams")
    else
      write_yaml(YAML.dump(self_marker))
      progress.complete("No metrics collected for #{teams_size} teams")
    end
  end

  def collect_team_metrics(project_key, emails)
    jira_users = find_jira_users(emails)

    created_counts = []
    resolved_counts = []

    # Generate month ranges for the last N months
    months = generate_month_ranges(@months_to_analyze)

    months.each do |month_start, month_end|
      created = count_issues(project_key, jira_users, "created", month_start, month_end)
      resolved = count_issues(project_key, jira_users, "resolved", month_start, month_end)

      created_counts << created
      resolved_counts << resolved
    end

    { created: created_counts, resolved: resolved_counts }
  end

  def generate_month_ranges(num_months)
    ranges = []
    today = Date.today

    num_months.times do |i|
      # Go back i+1 months (we don't include current incomplete month)
      month_date = today << (num_months - i)
      month_start = Date.new(month_date.year, month_date.month, 1)
      month_end = (month_start >> 1) - 1 # Last day of month

      ranges << [month_start, month_end]
    end

    ranges
  end

  def count_issues(project_key, jira_users, date_field, start_date, end_date)
    return 0 if jira_users.empty?

    user_list = jira_users.map { |u| "\"#{u}\"" }.join(", ")

    # Build JQL for team members in the date range
    jql = "project = #{project_key} AND " \
          "(assignee IN (#{user_list}) OR reporter IN (#{user_list})) AND " \
          "#{date_field} >= #{start_date.strftime("%Y-%m-%d")} AND " \
          "#{date_field} <= #{end_date.strftime("%Y-%m-%d")}"

    rate_limit
    begin
      # Use maxResults=0 to just get the count
      result = jira_get("/rest/api/2/search?jql=#{CGI.escape(jql)}&maxResults=0")
      result["total"] || 0
    rescue StandardError => e
      progress.warn("Error counting #{date_field} issues: #{e.message}")
      0
    end
  end
end

Archsight::Import::Registry.register("jira-metrics", Archsight::Import::Handlers::JiraMetrics)
