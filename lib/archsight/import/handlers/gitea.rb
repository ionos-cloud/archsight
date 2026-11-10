# frozen_string_literal: true

require "fileutils"
require "net/http"
require "json"
require "uri"
require "openssl"
require_relative "../handler"
require_relative "../registry"
require_relative "cache_pruner"

# Gitea handler - lists repositories of a Gitea (or Forgejo) server and generates child Import resources
#
# Configuration:
#   import/config/host - Gitea host, e.g. "gitea.example.com" (required)
#   import/config/org - Organization (or user) to list; without it every repository the token can see is listed
#   import/config/scheme - "https" (default) or "http"
#   import/config/verifySSL - "false" to skip certificate verification (default: true)
#   import/config/rateLimitMs - Pause between API requests in milliseconds (default: 0)
#   import/config/repoOutputPath - Output path for repository handler results (e.g., "generated/repositories.yaml")
#   import/config/childCacheTime - Cache time for generated child imports (e.g., "1h", "30m")
#   import/config/fallbackTeam - Default team when no contributor match found (propagated to child imports)
#   import/config/botTeam - Team for bot-only repositories (propagated to child imports)
#   import/config/corporateAffixes - Comma-separated corporate username affixes for team matching (propagated to child imports)
#   import/config/defaultVisibility - Default visibility for non-public repos (default: "internal")
#   import/config/cacheRoot - Override for the local git cache root (default: ~/.cache/archsight/git)
#
# Environment:
#   GITEA_TOKEN - Gitea access token (required)
#     Create at: <host>/user/settings/applications (scope read:repository, plus read:organization for `org`)
#
# Output:
#   Generates Import:Repo:* resources for each repository
#   The repository handler will clone/sync the actual git repositories (over SSH, so the SSH keys must work)
#
# Before generating imports, prunes any cache subdirectory under
# cacheRoot/gitea/<host>/<owner> that no longer corresponds to a repo returned by
# the API (e.g. a repo that was renamed or deleted), so stale clones don't
# linger and get picked up by later importers.
class Archsight::Import::Handlers::Gitea < Archsight::Import::Handler
  # generates child imports (see Handler.generates_imports?)
  def self.generates_imports? = true

  include Archsight::Import::Handlers::CachePruner

  # Gitea caps the page size (50 by default), so the listing runs until an empty page
  PER_PAGE = 50

  def execute
    @host = config("host")
    raise "Missing required config: host" unless @host

    @token = ENV.fetch("GITEA_TOKEN", nil)
    raise "Missing required environment variable: GITEA_TOKEN" unless @token

    @org = config("org")
    @scheme = config("scheme", default: "https")
    @verify_ssl = config("verifySSL", default: "true").to_s != "false"
    @rate_limit_ms = config("rateLimitMs", default: "0").to_i
    @repo_output_path = config("repoOutputPath")
    @child_cache_time = config("childCacheTime")
    @default_visibility = config("defaultVisibility", default: "internal")
    @host_dir = File.join(Archsight::Import.cache_root(config("cacheRoot")), "gitea", @host)

    progress.update("Fetching repositories from #{@org || @host}")
    repos = fetch_all_repos

    if repos.empty?
      progress.warn("No repositories found in #{@org || @host}")
      return
    end

    prune_stale_cache(repos)

    progress.update("Generating #{repos.size} import resources")
    generate_repository_imports(repos)

    write_generates_meta
  end

  private

  def fetch_all_repos
    repos = {}
    page = 1

    loop do
      progress.update("Fetching repositories (page #{page})")
      batch = fetch_repos_page(page)
      break if batch.empty?

      before = repos.size
      batch.each { |repo| repos[repo["id"] || repo["fullName"]] = repo }
      break if repos.size == before # a server that ignores `page` would repeat the first one forever

      progress.update("Fetched #{repos.size} repositories")
      page += 1
      sleep(@rate_limit_ms / 1000.0) if @rate_limit_ms.positive?
    end

    repos.values
  end

  def fetch_repos_page(page)
    data = if @org
             make_request("/orgs/#{URI.encode_www_form_component(@org)}/repos", page: page, limit: PER_PAGE)
           else
             # the search wraps the repositories: { ok: true, data: [...] }
             make_request("/repos/search", page: page, limit: PER_PAGE)["data"]
           end

    Array(data).map do |repo|
      {
        "id" => repo["id"],
        "name" => repo["name"],
        "fullName" => repo["full_name"],
        "owner" => repo.dig("owner", "login") || repo["full_name"].to_s.split("/").first,
        "isArchived" => repo["archived"],
        "private" => repo["private"],
        "sshUrl" => repo["ssh_url"],
        "url" => repo["clone_url"] || repo["html_url"]
      }
    end
  end

  def make_request(path, params = {})
    uri = URI("#{@scheme}://#{@host}/api/v1#{path}")
    uri.query = URI.encode_www_form(params) unless params.empty?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl? && !@verify_ssl

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "token #{@token}"
    request["Accept"] = "application/json"

    handle_response(http.request(request))
  end

  def handle_response(response)
    case response
    when Net::HTTPSuccess
      JSON.parse(response.body)
    when Net::HTTPUnauthorized
      raise "Gitea API error: 401 Unauthorized - Invalid or expired GITEA_TOKEN"
    when Net::HTTPForbidden
      raise "Gitea API error: 403 Forbidden - Check token permissions"
    when Net::HTTPNotFound
      raise "Gitea API error: 404 Not Found - #{@org ? "Organization '#{@org}'" : "API"} not found or not accessible on #{@host}"
    else
      raise "Gitea API error: #{response.code} #{response.message}"
    end
  end

  # Each owner has its own directory; owners that are not listed are left alone
  def prune_stale_cache(repos)
    repos.group_by { |repo| repo["owner"] }.each do |owner, owned|
      prune_stale_cache_entries(File.join(@host_dir, owner), owned.map { |repo| repo["name"] })
    end
  end

  def generate_repository_imports(repos)
    yaml_documents = repos.map do |repo|
      child_annotations = {}
      child_annotations["import/outputPath"] = @repo_output_path if @repo_output_path
      child_annotations["import/cacheTime"] = @child_cache_time if @child_cache_time

      child_config = {
        "path" => File.join(@host_dir, repo["owner"], repo["name"]),
        "gitUrl" => repo["sshUrl"] || repo["url"],
        "archived" => repo["isArchived"].to_s,
        "visibility" => repo["private"] == false ? "open-source" : @default_visibility
      }
      child_config["fallbackTeam"] = config("fallbackTeam") if config("fallbackTeam")
      child_config["botTeam"] = config("botTeam") if config("botTeam")
      child_config["corporateAffixes"] = config("corporateAffixes") if config("corporateAffixes")

      import_yaml(
        name: "Import:Repo:gitea:#{repo["owner"]}:#{repo["name"]}",
        handler: "repository",
        config: child_config,
        annotations: child_annotations
      )
    end

    # Add self-marker with generated/at for caching
    yaml_documents << self_marker

    write_yaml(yaml_documents.map { |doc| YAML.dump(doc) }.join("\n"))
  end
end

Archsight::Import::Registry.register("gitea", Archsight::Import::Handlers::Gitea)
