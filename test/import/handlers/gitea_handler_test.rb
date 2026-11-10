# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "webmock/minitest"
require "archsight/import/handlers/gitea"
require "archsight/import/progress"

class GiteaHandlerTest < Minitest::Test
  HOST = "gitea.example.com"
  API = "https://#{HOST}/api/v1".freeze

  def setup
    @resources_dir = Dir.mktmpdir
    @original_token = ENV.fetch("GITEA_TOKEN", nil)
    ENV["GITEA_TOKEN"] = "test-token"
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
    if @original_token
      ENV["GITEA_TOKEN"] = @original_token
    else
      ENV.delete("GITEA_TOKEN")
    end
  end

  def repo(name, owner: "test-org", private: false, archived: false, id: nil)
    {
      "id" => id || name.hash.abs, "name" => name, "full_name" => "#{owner}/#{name}", "owner" => { "login" => owner },
      "archived" => archived, "private" => private,
      "ssh_url" => "git@#{HOST}:#{owner}/#{name}.git", "clone_url" => "https://#{HOST}/#{owner}/#{name}.git",
      "html_url" => "https://#{HOST}/#{owner}/#{name}"
    }
  end

  def stub_org(repos, org: "test-org")
    stub_request(:get, "#{API}/orgs/#{org}/repos?limit=50&page=1").to_return(status: 200, body: repos.to_json)
    stub_request(:get, "#{API}/orgs/#{org}/repos?limit=50&page=2").to_return(status: 200, body: [].to_json)
  end

  def output
    File.read(File.join(@resources_dir, "generated", "Import_Gitea.yaml"))
  end

  def test_missing_token_raises_error
    ENV.delete("GITEA_TOKEN")
    error = assert_raises(RuntimeError) { create_handler(org: "test-org").execute }

    assert_equal "Missing required environment variable: GITEA_TOKEN", error.message
  end

  def test_missing_host_raises_error
    error = assert_raises(RuntimeError) { create_handler(host: nil, org: "test-org").execute }

    assert_equal "Missing required config: host", error.message
  end

  def test_lists_an_organization_with_token_header_and_generates_child_imports
    stub_org([repo("repo1"), repo("repo2", private: true, archived: true)])
    stub_request(:get, "#{API}/orgs/test-org/repos?limit=50&page=1").with(headers: { "Authorization" => "token test-token" })
                                                                    .to_return(status: 200, body: [repo("repo1"), repo("repo2", private: true, archived: true)].to_json)
    create_handler(org: "test-org").execute

    assert_includes output, "Import:Repo:gitea:test-org:repo1"
    assert_includes output, "git@#{HOST}:test-org/repo1.git"
    assert_includes output, "open-source"
    assert_includes output, "Import:Repo:gitea:test-org:repo2"
    assert_match(/archived: 'true'|archived: "true"|archived: true/, output)
    assert_includes output, "internal"
  end

  def test_paginates_until_an_empty_page
    first = (1..50).map { |i| repo("r#{i}", id: i) }
    stub_request(:get, "#{API}/orgs/test-org/repos?limit=50&page=1").to_return(status: 200, body: first.to_json)
    stub_request(:get, "#{API}/orgs/test-org/repos?limit=50&page=2").to_return(status: 200, body: [repo("last", id: 99)].to_json)
    stub_request(:get, "#{API}/orgs/test-org/repos?limit=50&page=3").to_return(status: 200, body: [].to_json)
    create_handler(org: "test-org").execute

    assert_includes output, "Import:Repo:gitea:test-org:r50"
    assert_includes output, "Import:Repo:gitea:test-org:last"
  end

  def test_a_server_that_repeats_the_first_page_does_not_loop_forever
    stub_request(:get, %r{#{API}/orgs/test-org/repos}).to_return(status: 200, body: [repo("repo1", id: 1)].to_json)
    create_handler(org: "test-org").execute

    assert_includes output, "Import:Repo:gitea:test-org:repo1"
  end

  def test_without_org_searches_all_visible_repositories
    body = { "ok" => true, "data" => [repo("a", owner: "one", id: 1), repo("b", owner: "two", id: 2)] }.to_json
    stub_request(:get, "#{API}/repos/search?limit=50&page=1").to_return(status: 200, body: body)
    stub_request(:get, "#{API}/repos/search?limit=50&page=2").to_return(status: 200, body: { "ok" => true, "data" => [] }.to_json)
    create_handler(org: nil).execute

    assert_includes output, "Import:Repo:gitea:one:a"
    assert_includes output, "Import:Repo:gitea:two:b"
  end

  def test_http_error_handling
    { 401 => "401 Unauthorized", 403 => "403 Forbidden", 404 => "404 Not Found", 500 => "500" }.each do |code, text|
      stub_request(:get, "#{API}/orgs/test-org/repos?limit=50&page=1").to_return(status: code, body: "")
      error = assert_raises(RuntimeError) { create_handler(org: "test-org").execute }

      assert_includes error.message, "Gitea API error: #{text}"
    end
  end

  def test_propagates_team_config_to_child_imports
    stub_org([repo("repo1")])
    create_handler(org: "test-org", fallback_team: "Team:Platform", bot_team: "Team:Bots", corporate_affixes: "acme").execute

    assert_includes output, "Team:Platform"
    assert_includes output, "Team:Bots"
    assert_includes output, "acme"
  end

  def test_omits_team_config_when_not_set
    stub_org([repo("repo1")])
    create_handler(org: "test-org").execute

    refute_includes output, "fallbackTeam"
    refute_includes output, "botTeam"
  end

  def test_prunes_stale_cache_directory_for_renamed_repo
    cache_root = Dir.mktmpdir
    owner_dir = File.join(cache_root, "gitea", HOST, "test-org")
    FileUtils.mkdir_p(File.join(owner_dir, "stale-repo"))
    FileUtils.mkdir_p(File.join(owner_dir, "repo1"))
    old = Time.now - 7200
    File.utime(old, old, File.join(owner_dir, "stale-repo"))
    stub_org([repo("repo1")])
    create_handler(org: "test-org", cache_root: cache_root).execute

    refute_path_exists File.join(owner_dir, "stale-repo")
    assert_path_exists File.join(owner_dir, "repo1")
  ensure
    FileUtils.rm_rf(cache_root)
  end

  def test_pruning_leaves_owners_that_are_not_listed_alone
    cache_root = Dir.mktmpdir
    other = File.join(cache_root, "gitea", HOST, "other-owner", "old-repo")
    FileUtils.mkdir_p(other)
    old = Time.now - 7200
    File.utime(old, old, other)
    stub_org([repo("repo1")])
    create_handler(org: "test-org", cache_root: cache_root).execute

    assert_path_exists other
  ensure
    FileUtils.rm_rf(cache_root)
  end

  def test_the_clone_path_includes_host_and_owner
    cache_root = Dir.mktmpdir
    stub_org([repo("repo1")])
    create_handler(org: "test-org", cache_root: cache_root).execute

    assert_includes output, File.join(cache_root, "gitea", HOST, "test-org", "repo1")
  ensure
    FileUtils.rm_rf(cache_root)
  end

  def test_registered_as_gitea
    Archsight::Import::Registry.restore_builtin! # other tests clear the registry

    assert_equal Archsight::Import::Handlers::Gitea, Archsight::Import::Registry["gitea"]
  end

  private

  def create_handler(org:, host: HOST, fallback_team: nil, bot_team: nil, corporate_affixes: nil, cache_root: nil)
    annotations = { "import/handler" => "gitea", "import/config/repoOutputPath" => "generated/repos.yaml" }
    annotations["import/config/host"] = host if host
    annotations["import/config/org"] = org if org
    annotations["import/config/fallbackTeam"] = fallback_team if fallback_team
    annotations["import/config/botTeam"] = bot_team if bot_team
    annotations["import/config/corporateAffixes"] = corporate_affixes if corporate_affixes
    annotations["import/config/cacheRoot"] = cache_root if cache_root

    raw = { "apiVersion" => "architecture/v1alpha1", "kind" => "Import",
            "metadata" => { "name" => "Import:Gitea", "annotations" => annotations }, "spec" => {} }
    Archsight::Import::Handlers::Gitea.new(MockGiteaImport.new(raw), database: nil, resources_dir: @resources_dir,
                                                                     progress: Archsight::Import::Progress.new(output: StringIO.new))
  end

  class MockGiteaImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/gitea-test.yaml")
    end
  end
end
