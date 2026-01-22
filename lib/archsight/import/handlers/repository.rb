# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"
require_relative "../handler"
require_relative "../registry"
require_relative "../git_analytics"
require_relative "../team_matcher"

# Repository handler - clones/syncs and analyzes a git repository, generates a TechnologyArtifact
#
# Configuration:
#   import/config/path - Path where the git repository should be cloned
#   import/config/gitUrl - Git URL to clone from (if not already cloned)
#   import/config/archived - Optional "true" if repository is archived
#   import/config/visibility - Optional visibility (internal, public, open-source)
#   import/config/sccPath - Optional path to scc binary (default: scc)
#   import/config/fallbackTeam - Optional team name when no contributor match found
#   import/config/botTeam - Optional team name for bot-only repositories
class Archsight::Import::Handlers::Repository < Archsight::Import::Handler
  def execute
    @path = config("path")
    @git_url = config("gitUrl")
    raise "Missing required config: path" unless @path

    # Clone or update the repository if gitUrl is provided
    if @git_url
      begin
        sync_repository
        if @skip_analysis
          write_generates_meta
          return
        end
      rescue StandardError => e
        # Access denied or other git errors - create minimal artifact
        if access_denied_error?(e.message)
          progress.update("Access denied - creating minimal artifact")
          write_minimal_artifact(
            status: "inaccessible",
            reason: "Repository not accessible",
            error: e.message,
            visibility: "private"
          )
          write_generates_meta
          return
        end
        raise
      end
    end

    raise "Directory not found: #{@path}" unless File.directory?(@path)
    raise "Not a git repository: #{@path}" unless File.directory?(File.join(@path, ".git"))

    # Check if empty repository (no code)
    progress.update("Analyzing code")
    scc_data = run_scc(@path)
    estimated_cost = scc_data["estimatedCost"]
    if !estimated_cost.nil? && estimated_cost.to_f.zero?
      progress.update("No analyzable code - creating minimal artifact")
      write_minimal_artifact(
        status: "no-code",
        reason: "No analyzable source code found"
      )
      write_generates_meta
      return
    end

    # Run native git analytics
    progress.update("Analyzing git history")
    git_data = run_git_analytics(@path)

    # Match contributors to teams
    progress.update("Matching teams")
    team_result = match_teams(git_data["top_contributors"], git_data["activity_status"])

    # Build resource
    progress.update("Generating resource")
    resource = build_technology_artifact(@path, scc_data, git_data, team_result)

    # Write output with self-marker for caching
    yaml_content = YAML.dump(resource) + YAML.dump(self_marker)
    write_yaml(yaml_content)

    write_generates_meta
  end

  def sync_repository
    if File.directory?(File.join(@path, ".git"))
      # Update existing repository
      progress.update("Updating repository")
      update_repository
    else
      # Clone new repository
      progress.update("Cloning repository")
      clone_repository
    end

    # Check if repository is empty (no commits)
    return unless empty_repository?

    progress.update("Empty repository - creating minimal artifact")
    write_minimal_artifact(
      status: "empty",
      reason: "Repository has no commits"
    )
    @skip_analysis = true
  end

  def clone_repository
    FileUtils.mkdir_p(File.dirname(@path))
    run_git(%w[git clone --quiet] + [@git_url, @path], Dir.pwd)
  end

  def update_repository
    run_git(%w[git fetch --quiet], @path)
    return if empty_repository? # Skip merge for empty repos

    # Check if update is needed
    current_head = run_git(%w[git rev-parse HEAD], @path).strip
    fetch_head = run_git(%w[git rev-parse FETCH_HEAD], @path).strip
    return if current_head == fetch_head # Already up-to-date

    run_git(%w[git merge --ff-only FETCH_HEAD], @path)
  rescue StandardError => e
    # If merge fails (diverged history), reset to remote state
    progress.warn("Merge failed: #{e.message}, resetting to remote")
    run_git(%w[git reset --hard FETCH_HEAD], @path)
  end

  def empty_repository?
    # Check if HEAD exists (empty repos have no commits)
    _, _, status = Open3.capture3("git", "rev-parse", "HEAD", chdir: @path)
    !status.success?
  end

  # Run a git command safely using array form to prevent shell injection
  # @param command [Array<String>] Command and arguments as array
  # @param dir [String] Working directory
  # @return [String] Command output
  def run_git(command, dir)
    out, err, status = Open3.capture3(*command, chdir: dir)
    raise "Git command failed: #{sanitize_error(err)}" unless status.success?

    out
  end

  # Sanitize error message to prevent breaking TTY progress display
  def sanitize_error(message)
    return "" if message.nil? || message.empty?

    # Take first meaningful line, strip ANSI codes and remote prefixes
    lines = message.lines.map(&:strip).reject { |l| l.empty? || l.start_with?("remote:") }
    first_line = lines.first || message.lines.first&.strip || ""

    # Truncate if too long
    first_line.length > 100 ? "#{first_line[0, 97]}..." : first_line
  end

  # Check if error message indicates access denied
  def access_denied_error?(message)
    return false if message.nil?

    patterns = [
      /could not read from remote repository/i,
      /permission denied/i,
      /access denied/i,
      /authentication failed/i,
      /repository not found/i,
      /fatal: '.*' does not appear to be a git repository/i
    ]
    patterns.any? { |p| message.match?(p) }
  end

  # Write a minimal TechnologyArtifact for repositories that can't be fully analyzed
  # @param status [String] Activity status (inaccessible, empty, no-code)
  # @param reason [String] Human-readable reason
  # @param error [String, nil] Optional error message
  # @param visibility [String] Repository visibility (default: from config or "internal")
  def write_minimal_artifact(status:, reason:, error: nil, visibility: nil)
    git_url = @git_url
    vis = visibility || config("visibility", default: "internal")

    annotations = {
      "artifact/type" => "repo",
      "repository/git" => git_url,
      "repository/visibility" => vis,
      "activity/status" => status,
      "activity/reason" => reason,
      "generated/script" => import_resource.name,
      "generated/at" => Time.now.utc.iso8601
    }

    annotations["repository/accessible"] = "false" if status == "inaccessible"
    annotations["repository/error"] = sanitize_error(error) if error

    resource = resource_yaml(
      kind: "TechnologyArtifact",
      name: repository_name(git_url),
      annotations: annotations,
      spec: {}
    )

    # Write output with self-marker for caching
    yaml_content = YAML.dump(resource) + YAML.dump(self_marker)
    write_yaml(yaml_content)
  end

  private

  def run_scc(path)
    cmd = ["scc", "-f", "json2", "--sort", "name", path]

    out, err, status = Open3.capture3(*cmd)
    raise "scc failed: #{cmd.join(" ")}\n#{err}" unless status.success?

    return empty_scc_result if out.strip.empty?

    JSON.parse(out)
  rescue JSON::ParserError => e
    raise "Failed to parse scc output for #{path}: #{e.message}"
  end

  def empty_scc_result
    {
      "languageSummary" => [],
      "estimatedCost" => 0,
      "estimatedPeople" => 0,
      "estimatedScheduleMonths" => 0
    }
  end

  def run_git_analytics(path)
    Archsight::Import::GitAnalytics.new(path).analyze
  rescue StandardError => e
    progress.warn("Git analytics failed: #{e.message}")
    empty_git_analytics_result
  end

  def empty_git_analytics_result
    {
      "activity_status" => "unknown",
      "bus_factor_risk" => "unknown",
      "commits_per_month" => [],
      "contributors_per_month" => [],
      "contributors_6m" => 0,
      "contributors" => 0,
      "top_contributors" => [],
      "deployment_types" => "none",
      "workflow_platforms" => "none",
      "workflow_types" => "none",
      "agentic_tools" => "none"
    }
  end

  def match_teams(top_contributors, activity_status)
    return nil unless database && top_contributors&.any?

    matcher = Archsight::Import::TeamMatcher.new(database)
    result = matcher.analyze(top_contributors)

    # Apply fallbacks from config
    if result[:maintainer].nil?
      fallback = if activity_status == "bot-only"
                   config("botTeam") || config("fallbackTeam")
                 else
                   config("fallbackTeam")
                 end
      result[:maintainer] = fallback
    end

    result
  end

  def build_technology_artifact(path, scc_data, git_data, team_result = nil)
    annotations = {}

    # Artifact type
    annotations["artifact/type"] = "repo"

    # Repository URL from git config
    git_url = extract_git_url(path)
    annotations["repository/git"] = git_url if git_url

    # Visibility
    visibility = config("visibility", default: determine_visibility(git_url))
    annotations["repository/visibility"] = visibility

    # SCC metrics
    annotations.merge!(build_scc_annotations(scc_data))

    # Git activity metrics
    annotations.merge!(build_activity_annotations(git_data))

    # Deployment annotations
    annotations.merge!(build_deployment_annotations(git_data))

    # Generated metadata
    annotations["generated/script"] = import_resource.name
    annotations["generated/at"] = Time.now.utc.iso8601

    # Build spec
    spec = {}

    # Technology component (Git provider)
    if git_url
      provider = git_url.include?("github") ? "Git:Github" : "Git:Gitlab"
      spec["suppliedBy"] = { "technologyComponents" => [provider] }
    end

    # Team relations from contributor matching
    if team_result
      spec["maintainedBy"] = { "businessActors" => [team_result[:maintainer]] } if team_result[:maintainer]
      spec["contributedBy"] = { "businessActors" => team_result[:contributors] } if team_result[:contributors]&.any?
    end

    resource_yaml(
      kind: "TechnologyArtifact",
      name: repository_name(git_url || path),
      annotations: annotations,
      spec: spec
    )
  end

  def extract_git_url(path)
    config_path = File.join(path, ".git", "config")
    return nil unless File.exist?(config_path)

    config_content = File.read(config_path)
    url_line = config_content.lines.find { |l| l.include?("url") }
    return nil unless url_line

    url_line.split("=").last.strip
  end

  def repository_name(git_url_or_path)
    if git_url_or_path.include?(":")
      # Git URL format
      name = git_url_or_path.split(":").last.gsub(/.git$/, "").gsub(%r{/}, ":")
      "Repo:#{name}"
    else
      # Path format - use directory name
      "Repo:#{File.basename(git_url_or_path)}"
    end
  end

  def determine_visibility(git_url)
    return "internal" unless git_url
    return "internal" unless git_url.include?("github")

    # Default to internal, can be overridden by config
    "internal"
  end

  def build_scc_annotations(scc_data)
    annotations = {}

    languages = (scc_data["languageSummary"] || []).map { |l| l["Name"] }
    annotations["scc/languages"] = languages.join(",") unless languages.empty?

    annotations["scc/estimatedCost"] = format("%.2f", scc_data["estimatedCost"].to_f)
    annotations["scc/estimatedScheduleMonths"] = format("%.2f", scc_data["estimatedScheduleMonths"].to_f)
    annotations["scc/estimatedPeople"] = format("%.2f", scc_data["estimatedPeople"].to_f)

    # Per-language LOC
    (scc_data["languageSummary"] || []).each do |lang|
      annotations["scc/language/#{lang["Name"]}/loc"] = lang["Code"].to_s
    end

    annotations
  end

  def build_activity_annotations(git_data)
    annotations = {}

    # Activity status - check if archived first
    archived = config("archived") == "true"
    activity_status = archived ? "archived" : (git_data["activity_status"] || "unknown")
    annotations["activity/status"] = activity_status

    # Commit metrics
    annotations["activity/commits"] = git_data["commits_per_month"].join(",") if git_data["commits_per_month"]&.any?

    # Contributor metrics
    annotations["activity/contributors"] = git_data["contributors_per_month"].join(",") if git_data["contributors_per_month"]&.any?
    annotations["activity/contributors/6m"] = git_data["contributors_6m"].to_s if git_data["contributors_6m"]
    annotations["activity/contributors/total"] = git_data["contributors"].to_s if git_data["contributors"]

    # Health metrics
    annotations["activity/busFactor"] = git_data["bus_factor_risk"] if git_data["bus_factor_risk"]
    annotations["agentic/tools"] = git_data["agentic_tools"] if git_data["agentic_tools"]

    # Timestamps
    annotations["activity/createdAt"] = git_data["created_at"] if git_data["created_at"]
    annotations["activity/lastHumanCommit"] = git_data["last_human_commit"] if git_data["last_human_commit"]

    # Recent tags (for release info)
    if git_data["recent_tags"]&.any?
      tag_names = git_data["recent_tags"].map { |t| t["name"] }
      annotations["repository/recentTags"] = tag_names.join(",")
    end

    annotations
  end

  def build_deployment_annotations(git_data)
    annotations = {}

    annotations["repository/artifacts"] = git_data["deployment_types"] if git_data["deployment_types"]
    annotations["workflow/platforms"] = git_data["workflow_platforms"] if git_data["workflow_platforms"]
    annotations["workflow/types"] = git_data["workflow_types"] if git_data["workflow_types"]

    annotations["deployment/images"] = git_data["oci_images"].join(",") if git_data["oci_images"]&.any?

    annotations["architecture/description"] = git_data["description"] if git_data["description"] && !git_data["description"].empty?

    # Documentation links (handle potential key collisions)
    (git_data["documentation_links"] || []).each do |link|
      base_name = if link["text"] && !link["text"].empty?
                    link["text"]
                  else
                    link["url"].sub(%r{^https?://}, "").gsub("/", "-")
                  end

      # Find unique key by adding numeric suffix if needed
      key = "link/#{base_name}"
      if annotations.key?(key)
        counter = 2
        counter += 1 while annotations.key?("link/#{base_name}-#{counter}")
        key = "link/#{base_name}-#{counter}"
      end
      annotations[key] = link["url"]
    end

    annotations
  end
end

Archsight::Import::Registry.register("repository", Archsight::Import::Handlers::Repository)
