# frozen_string_literal: true

require "fileutils"
require "net/http"
require "json"
require "uri"
require "openssl"
require_relative "../handler"
require_relative "../registry"

# GitHub handler - lists repositories from a GitHub organization and generates child Import resources
#
# Configuration:
#   import/config/org - GitHub organization name
#   import/config/repoOutputPath - Output path for repository handler results (e.g., "generated/repositories.yaml")
#   import/config/childCacheTime - Cache time for generated child imports (e.g., "1h", "30m")
#
# Environment:
#   GITHUB_TOKEN - GitHub Personal Access Token (required)
#     Create at: https://github.com/settings/tokens
#     Required scopes: repo (private repos) or public_repo (public only)
#
# Output:
#   Generates Import:Repo:* resources for each repository, with dependsOn to this import
#   The repository handler will clone/sync the actual git repositories
class Archsight::Import::Handlers::Github < Archsight::Import::Handler
  PER_PAGE = 100

  def execute
    @org = config("org")
    raise "Missing required config: org" unless @org

    @token = ENV.fetch("GITHUB_TOKEN", nil)
    raise "Missing required environment variable: GITHUB_TOKEN" unless @token

    @repo_output_path = config("repoOutputPath")
    @child_cache_time = config("childCacheTime")
    @target_dir = File.join(Dir.home, ".cache", "archsight", "git", "github", @org)

    # Fetch all repositories with pagination
    progress.update("Fetching repositories from #{@org}")
    repos = fetch_all_repos

    if repos.empty?
      progress.warn("No repositories found in #{@org}")
      return
    end

    # Generate Import resources for each repository
    progress.update("Generating #{repos.size} import resources")
    generate_repository_imports(repos)
  end

  private

  def fetch_all_repos
    all_repos = []
    page = 1

    loop do
      progress.update("Fetching repositories (page #{page})")
      batch = fetch_repos_page(page)
      break if batch.empty?

      all_repos.concat(batch)
      progress.update("Fetched #{all_repos.size} repositories")
      break if batch.size < PER_PAGE

      page += 1
    end

    all_repos
  end

  def fetch_repos_page(page)
    data = make_request("/orgs/#{@org}/repos", per_page: PER_PAGE, page: page)

    # Transform API response to match expected format
    data.map do |repo|
      {
        "name" => repo["name"],
        "isArchived" => repo["archived"],
        "visibility" => repo["visibility"],
        "sshUrl" => repo["ssh_url"],
        "url" => repo["html_url"]
      }
    end
  end

  def make_request(path, params = {})
    uri = URI("https://api.github.com#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@token}"
    request["Accept"] = "application/vnd.github+json"
    request["X-GitHub-Api-Version"] = "2022-11-28"

    response = http.request(request)
    handle_response(response)
  end

  def handle_response(response)
    case response
    when Net::HTTPSuccess
      JSON.parse(response.body)
    when Net::HTTPUnauthorized
      raise "GitHub API error: 401 Unauthorized - Invalid or expired GITHUB_TOKEN"
    when Net::HTTPForbidden
      if response["X-RateLimit-Remaining"] == "0"
        reset_time = Time.at(response["X-RateLimit-Reset"].to_i)
        raise "GitHub API error: 403 Rate limit exceeded. Resets at #{reset_time}"
      end
      raise "GitHub API error: 403 Forbidden - Check token permissions"
    when Net::HTTPNotFound
      raise "GitHub API error: 404 Not Found - Organization '#{@org}' not found or not accessible"
    else
      raise "GitHub API error: #{response.code} #{response.message}"
    end
  end

  def generate_repository_imports(repos)
    yaml_documents = repos.map do |repo|
      repo_name = repo["name"]
      repo_path = File.join(@target_dir, repo_name)
      visibility = (repo["visibility"] || "private").downcase
      git_url = repo["sshUrl"] || repo["url"]

      # Build annotations for child import
      child_annotations = {}
      child_annotations["import/outputPath"] = @repo_output_path if @repo_output_path
      child_annotations["import/cacheTime"] = @child_cache_time if @child_cache_time

      import_yaml(
        name: "Import:Repo:github:#{@org}:#{repo_name}",
        handler: "repository",
        config: {
          "path" => repo_path,
          "gitUrl" => git_url,
          "archived" => repo["isArchived"].to_s,
          "visibility" => visibility == "public" ? "open-source" : "internal"
        },
        annotations: child_annotations,
        depends_on: [import_resource.name]
      )
    end

    # Add self-marker with generated/at for caching
    yaml_documents << self_marker

    # Write all imports to a single file with --- separators
    yaml_content = yaml_documents.map { |doc| YAML.dump(doc) }.join("\n")
    write_yaml(yaml_content)
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

Archsight::Import::Registry.register("github", Archsight::Import::Handlers::Github)
