# frozen_string_literal: true

require "open3"
require "fileutils"
require "net/http"
require "json"
require "uri"
require "openssl"
require_relative "../handler"
require_relative "../registry"

# GitLab handler - lists repositories from a GitLab instance and generates child Import resources
#
# Configuration:
#   import/config/host - GitLab host (e.g., gitlab.company.com)
#   import/config/exploreGroups - If "true", explore all visible groups (default: false)
#   import/config/perPage - API pagination page size (default: 100)
#   import/config/verifySSL - If "false", disable SSL verification (default: true)
#   import/config/sslFingerprint - SSL certificate fingerprint for pinning (SHA256, colon-separated hex)
#   import/config/repoOutputPath - Output path for repository handler results (e.g., "generated/repositories.yaml")
#   import/config/childCacheTime - Cache time for generated child imports (e.g., "1h", "30m")
#   import/config/fallbackTeam - Default team when no contributor match found (propagated to child imports)
#   import/config/botTeam - Team for bot-only repositories (propagated to child imports)
#   import/config/corporateAffixes - Comma-separated corporate username affixes for team matching (propagated to child imports)
#
# Environment:
#   GITLAB_TOKEN - GitLab personal access token (required)
#
# Output:
#   Generates Import:Repo:* resources for each repository
#   The repository handler will clone/sync the actual git repositories (via SSH)
class Archsight::Import::Handlers::Gitlab < Archsight::Import::Handler
  def execute
    @host = config("host")
    raise "Missing required config: host" unless @host

    @token = ENV.fetch("GITLAB_TOKEN", nil)
    raise "Missing required environment variable: GITLAB_TOKEN" unless @token

    @repo_output_path = config("repoOutputPath")
    @child_cache_time = config("childCacheTime")

    @target_dir = File.join(Dir.home, ".cache", "archsight", "git", "gitlab")
    @explore_groups = config("exploreGroups") == "true"
    @per_page = config("perPage", default: "100").to_i
    @verify_ssl = config("verifySSL") != "false"
    @ssl_fingerprint = config("sslFingerprint")

    # Fetch all projects
    progress.update("Fetching projects from #{@host}")
    projects = fetch_all_projects

    if projects.empty?
      progress.warn("No projects found on GitLab")
      return
    end

    # Generate Import resources for each repository
    progress.update("Generating #{projects.size} import resources")
    generate_repository_imports(projects)

    write_generates_meta
  end

  private

  def api_endpoint
    "https://#{@host}/api/v4"
  end

  def make_request(path, params = {})
    uri = URI("#{api_endpoint}#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    # Configure SSL verification
    if @ssl_fingerprint
      # Use certificate pinning - disable default verification, we verify fingerprint manually
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.verify_callback = lambda do |_preverify_ok, cert_store|
        # Get the peer certificate from the chain
        cert = cert_store.chain&.first
        return true unless cert # Allow if no cert (will fail later)

        # Compute SHA256 fingerprint
        fingerprint = OpenSSL::Digest::SHA256.new(cert.to_der).to_s.upcase.scan(/../).join(":")
        expected = @ssl_fingerprint.upcase

        raise OpenSSL::SSL::SSLError, "Certificate fingerprint mismatch! Expected: #{expected}, Got: #{fingerprint}" if fingerprint != expected

        true
      end
    else
      http.verify_mode = @verify_ssl ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    end

    request = Net::HTTP::Get.new(uri)
    request["PRIVATE-TOKEN"] = @token

    response = http.request(request)

    raise "GitLab API error: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def fetch_all_groups
    groups = []
    page = 1

    loop do
      progress.update("Fetching groups (page #{page})")
      params = { per_page: @per_page, page: page }
      params[:all_available] = true if @explore_groups

      batch = make_request("/groups", params)
      break if batch.empty?

      groups.concat(batch)
      page += 1
    end

    groups
  end

  def fetch_projects_for_group(group_id)
    projects = []
    page = 1

    loop do
      params = {
        include_subgroups: true,
        per_page: @per_page,
        page: page,
        order_by: "created_at"
      }

      batch = make_request("/groups/#{group_id}/projects", params)
      break if batch.empty?

      projects.concat(batch)
      page += 1
    end

    projects
  end

  def fetch_all_projects
    all_projects = []
    groups = fetch_all_groups

    groups.each_with_index do |group, idx|
      progress.update("Fetching projects from #{group["full_path"]}", current: idx + 1, total: groups.size)
      projects = fetch_projects_for_group(group["id"])
      all_projects.concat(projects)
    end

    # Deduplicate by project ID
    all_projects.uniq { |p| p["id"] }
  end

  def safe_dir_name(path)
    path.gsub("/", ".")
  end

  def git_url_for(project)
    project["ssh_url_to_repo"]
  end

  def generate_repository_imports(projects)
    yaml_documents = projects.map do |project|
      dir_name = safe_dir_name(project["path_with_namespace"])
      repo_path = File.join(@target_dir, dir_name)
      git_url = git_url_for(project)

      # Build annotations for child import
      child_annotations = {}
      child_annotations["import/outputPath"] = @repo_output_path if @repo_output_path
      child_annotations["import/cacheTime"] = @child_cache_time if @child_cache_time

      child_config = {
        "path" => repo_path,
        "gitUrl" => git_url,
        "archived" => project["archived"].to_s,
        "visibility" => project["visibility"] || "internal"
      }
      child_config["fallbackTeam"] = config("fallbackTeam") if config("fallbackTeam")
      child_config["botTeam"] = config("botTeam") if config("botTeam")
      child_config["corporateAffixes"] = config("corporateAffixes") if config("corporateAffixes")

      import_yaml(
        name: "Import:Repo:gitlab:#{dir_name}",
        handler: "repository",
        config: child_config,
        annotations: child_annotations
      )
    end

    # Add self-marker with generated/at for caching
    yaml_documents << self_marker

    # Write all imports to a single file with --- separators
    yaml_content = yaml_documents.map { |doc| YAML.dump(doc) }.join("\n")
    write_yaml(yaml_content)
  end
end

Archsight::Import::Registry.register("gitlab", Archsight::Import::Handlers::Gitlab)
