# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "cgi"

require_relative "../handler"

# Shared module for Jira handlers
#
# Provides common functionality for Jira API interactions including:
# - HTTP client with Bearer token authentication
# - User lookup and caching (email -> Jira username)
# - Project info lookup and caching
# - Team loading and email extraction
# - Rate limiting
module Archsight::Import::Handlers::JiraBase
  # Initialize Jira client
  # @param host [String] Jira host (e.g., "hosting-jira.1and1.org")
  # @param token [String] Jira Bearer token
  # @param rate_limit_ms [Integer] Rate limit delay in milliseconds
  def init_jira_client(host:, token:, rate_limit_ms: 100)
    @jira_host = host
    @jira_token = token
    @rate_limit_ms = rate_limit_ms
    @jira_uri = URI("https://#{host}")
    @jira_http = Net::HTTP.new(@jira_uri.host, @jira_uri.port)
    @jira_http.use_ssl = true
    @jira_http.read_timeout = 120
    @user_cache = {}
    @project_cache = {}
  end

  # Make a GET request to the Jira API
  # @param path [String] API path (e.g., "/rest/api/2/myself")
  # @return [Hash, Array] Parsed JSON response
  # @raise [RuntimeError] on HTTP errors
  def jira_get(path)
    request = Net::HTTP::Get.new(path)
    request["Authorization"] = "Bearer #{@jira_token}"
    request["Content-Type"] = "application/json"
    response = @jira_http.request(request)

    raise "Jira API error: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  # Verify Jira credentials by calling /rest/api/2/myself
  # @return [Hash] User info from Jira
  # @raise [RuntimeError] on authentication failure
  def verify_jira_credentials
    progress.update("Verifying Jira credentials...")
    user = jira_get("/rest/api/2/myself")
    progress.update("Authenticated as #{user["displayName"] || user["name"]}")
    user
  rescue StandardError => e
    raise "Jira authentication failed: #{e.message}"
  end

  # Find Jira usernames for a list of email addresses
  # @param emails [Array<String>] Email addresses to look up
  # @return [Array<String>] Jira usernames
  def find_jira_users(emails)
    users = []

    emails.each do |email|
      # Check cache first
      if @user_cache.key?(email)
        users << @user_cache[email] if @user_cache[email]
        next
      end

      rate_limit
      begin
        result = jira_get("/rest/api/2/user/search?username=#{CGI.escape(email)}&maxResults=1")

        if result&.any?
          user = result.first
          username = user["name"] || user["accountId"]
          @user_cache[email] = username
          users << username
        else
          @user_cache[email] = nil
        end
      rescue StandardError => e
        progress.warn("Error searching for user #{email}: #{e.message}")
        @user_cache[email] = nil
      end
    end

    users.compact.uniq
  end

  # Get project info from Jira API
  # @param project_key [String] Project key
  # @return [Hash, nil] Project info or nil if not found
  def get_project_info(project_key)
    return @project_cache[project_key] if @project_cache.key?(project_key)

    rate_limit
    begin
      project = jira_get("/rest/api/2/project/#{project_key}")
      @project_cache[project_key] = project
      project
    rescue StandardError => e
      progress.warn("Error fetching project #{project_key}: #{e.message}")
      @project_cache[project_key] = nil
      nil
    end
  end

  # Extract email addresses from a team's annotations
  # @param team [Archsight::Resources::Base] Team resource
  # @return [Array<String>] Unique email addresses
  def extract_team_emails(team)
    emails = []

    if (lead = team.annotations["team/lead"])
      email = extract_email(lead)
      emails << email if email
    end

    if (members = team.annotations["team/members"])
      members.each_line do |line|
        line = line.strip
        next if line.empty?

        email = extract_email(line)
        emails << email if email
      end
    end

    emails.compact.uniq
  end

  # Load teams from database with optional filter
  # @param ignored_teams [Array<String>] Team names to ignore
  # @param require_jira [Boolean] If true, only return teams WITH team/jira
  # @param require_no_jira [Boolean] If true, only return teams WITHOUT team/jira
  # @return [Array<Archsight::Resources::Base>] Filtered and sorted teams
  def load_teams(ignored_teams: [], require_jira: false, require_no_jira: false)
    teams = database.instances_by_kind("BusinessActor")

    filtered = teams.values.reject do |team|
      next true if ignored_teams.include?(team.name)
      next true if extract_team_emails(team).empty?

      jira_project = team.annotations["team/jira"]
      has_jira = jira_project && !jira_project.empty?

      next true if require_jira && !has_jira
      next true if require_no_jira && has_jira

      false
    end

    filtered.sort_by(&:name)
  end

  # Parse comma-separated config values
  # @param value [String, nil] Comma-separated values
  # @return [Array<String>] Parsed array
  def parse_list_config(value)
    return [] if value.nil? || value.empty?

    value.split(",").map(&:strip)
  end

  # Apply rate limiting between API calls
  def rate_limit
    sleep(@rate_limit_ms / 1000.0)
  end

  private

  # Extract email from a member string
  # Handles formats like "Name <email@example.com>" or "email@example.com"
  # @param member_str [String] Member string
  # @return [String, nil] Extracted email or nil
  def extract_email(member_str)
    if member_str =~ /<([^>]+)>/
      Regexp.last_match(1).strip.downcase
    elsif member_str =~ /@/
      member_str.strip.downcase
    end
  end
end
