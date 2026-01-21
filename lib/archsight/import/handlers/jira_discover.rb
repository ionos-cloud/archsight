# frozen_string_literal: true

require_relative "../handler"
require_relative "../registry"
require_relative "jira_base"

# Jira Discover handler - discovers Jira projects for teams without team/jira set
#
# Configuration:
#   import/config/host - Jira host (required, e.g., "hosting-jira.1and1.org")
#   import/config/minActivityThreshold - Minimum issues for valid project (default: 5)
#   import/config/excludedProjectCategories - Comma-separated category IDs to exclude
#   import/config/excludedProjects - Comma-separated project keys to exclude
#   import/config/ignoredTeams - Comma-separated team names to skip
#   import/config/rateLimitMs - API rate limit delay (default: 100)
#
# Environment:
#   JIRA_TOKEN - Jira Personal Access Token (required)
#
# Output:
#   BusinessActor patches with team/jira annotation
class Archsight::Import::Handlers::JiraDiscover < Archsight::Import::Handler
  include Archsight::Import::Handlers::JiraBase

  def execute
    load_configuration
    verify_jira_credentials
    discover_projects
  end

  private

  def load_configuration
    @host = config("host")
    raise "Missing required config: host" unless @host

    @token = ENV.fetch("JIRA_TOKEN", nil)
    raise "Missing required environment variable: JIRA_TOKEN" unless @token

    @min_activity_threshold = config("minActivityThreshold", default: "5").to_i
    @excluded_project_categories = parse_list_config(config("excludedProjectCategories"))
    @excluded_projects = parse_list_config(config("excludedProjects"))
    @ignored_teams = parse_list_config(config("ignoredTeams"))
    @rate_limit_ms = config("rateLimitMs", default: "100").to_i

    init_jira_client(host: @host, token: @token, rate_limit_ms: @rate_limit_ms)
  end

  def discover_projects
    teams = load_teams(ignored_teams: @ignored_teams, require_no_jira: true)

    if teams.empty?
      progress.warn("No teams found without Jira project configured")
      # Still write self-marker for caching
      write_yaml(YAML.dump(self_marker))
      return
    end

    progress.update("Found #{teams.size} teams without Jira project configured")

    documents = []
    discovered_count = 0

    teams.each_with_index do |team, idx|
      emails = extract_team_emails(team)
      progress.update("[#{idx + 1}/#{teams.size}] Processing #{team.name}...")

      project_key = discover_team_project(team.name, emails)

      next unless project_key

      project_info = get_project_info(project_key)
      project_name = project_info&.dig("name") || ""

      documents << {
        "apiVersion" => "architecture/v1alpha1",
        "kind" => "BusinessActor",
        "metadata" => {
          "name" => team.name,
          "annotations" => {
            "team/jira" => project_key,
            "generated/script" => import_resource.name,
            "generated/at" => Time.now.utc.iso8601
          }
        }
      }
      discovered_count += 1
      progress.update("[#{idx + 1}/#{teams.size}] #{team.name} -> #{project_key} (#{project_name})")
    end

    # Add self-marker for caching
    documents << self_marker

    if documents.size > 1
      yaml_content = documents.map { |doc| YAML.dump(doc) }.join("\n")
      write_yaml(yaml_content)
      progress.complete("Discovered Jira projects for #{discovered_count}/#{teams.size} teams")
    else
      # Still write self-marker even if no projects discovered
      write_yaml(YAML.dump(self_marker))
      progress.complete("No Jira projects discovered for #{teams.size} teams")
    end
  end

  def discover_team_project(team_name, emails)
    jira_users = find_jira_users(emails)
    return nil if jira_users.empty?

    project_activity = Hash.new(0)

    # Build JQL to find issues where team members are assignee or reporter
    user_list = jira_users.map { |u| "\"#{u}\"" }.join(", ")
    jql = "(assignee IN (#{user_list}) OR reporter IN (#{user_list})) AND updated >= -26w"

    rate_limit
    begin
      # Get issues to count by project
      result = jira_get("/rest/api/2/search?jql=#{CGI.escape(jql)}&maxResults=500&fields=project")
      issues = result["issues"] || []
      issues.each do |issue|
        project_key = issue.dig("fields", "project", "key")
        project_activity[project_key] += 1 if project_key
      end
    rescue StandardError => e
      progress.warn("Error querying issues for #{team_name}: #{e.message}")
      return nil
    end

    return nil if project_activity.empty?

    # Filter out excluded project categories and find project with most activity
    sorted_projects = project_activity.sort_by { |_, count| -count }

    sorted_projects.each do |project_key, count|
      next if excluded_project?(project_key)
      next if count < @min_activity_threshold

      return project_key
    end

    nil
  end

  def excluded_project?(project_key)
    # Check if project key is explicitly excluded
    return true if @excluded_projects.include?(project_key)

    # Check if project category is excluded
    return false if @excluded_project_categories.empty?

    project_info = get_project_info(project_key)
    return false unless project_info

    category_id = project_info.dig("projectCategory", "id")&.to_s
    @excluded_project_categories.include?(category_id)
  end

  # Generate a marker Import for this handler with generated/at timestamp
  # This is merged with the original Import to enable cache checking
  def self_marker
    {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => import_resource.name,
        "annotations" => {
          "generated/at" => Time.now.utc.iso8601
        }
      },
      "spec" => {}
    }
  end
end

Archsight::Import::Registry.register("jira-discover", Archsight::Import::Handlers::JiraDiscover)
