# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "archsight/import/git_analytics"

class GitAnalyticsTest < Minitest::Test
  def setup
    @repo_dir = Dir.mktmpdir
    setup_git_repo
  end

  def teardown
    FileUtils.rm_rf(@repo_dir)
  end

  def test_analyze_returns_hash_with_expected_keys
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    expected_keys = %w[
      commits commits_per_month contributors contributors_6m
      contributors_per_month top_contributors recent_tags
      activity_status created_at last_human_commit bus_factor_risk
      agentic_tools deployment_types workflow_platforms
      workflow_types oci_images description documentation_links
    ]

    expected_keys.each do |key|
      assert result.key?(key), "Expected result to have key '#{key}'"
    end
  end

  def test_commit_count
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_equal 2, result["commits"]
  end

  def test_contributor_count
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_equal 1, result["contributors"]
  end

  def test_top_contributors_includes_name_and_email
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_kind_of Array, result["top_contributors"]
    assert_predicate result["top_contributors"], :any?

    contributor = result["top_contributors"].first

    assert contributor.key?("name")
    assert contributor.key?("email")
    assert contributor.key?("commits")
    assert_equal "Test User", contributor["name"]
    assert_equal "test@example.com", contributor["email"]
  end

  def test_activity_status_is_active_with_recent_commits
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_equal "active", result["activity_status"]
  end

  def test_bus_factor_risk_high_with_single_contributor
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_equal "high", result["bus_factor_risk"]
  end

  def test_deployment_types_includes_container_when_dockerfile_exists
    File.write(File.join(@repo_dir, "Dockerfile"), "FROM alpine\n")
    git_add_commit("Add Dockerfile")

    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_includes result["deployment_types"], "container"
  end

  def test_deployment_types_is_none_when_no_deployment_files
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_equal "none", result["deployment_types"]
  end

  def test_workflow_platforms_includes_github_actions
    FileUtils.mkdir_p(File.join(@repo_dir, ".github/workflows"))
    File.write(File.join(@repo_dir, ".github/workflows/ci.yml"), "name: CI\n")
    git_add_commit("Add GitHub Actions")

    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_includes result["workflow_platforms"], "github-actions"
  end

  def test_agentic_tools_detects_claude_md
    File.write(File.join(@repo_dir, "CLAUDE.md"), "# Claude Instructions\n")
    git_add_commit("Add CLAUDE.md")

    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_includes result["agentic_tools"], "claude"
  end

  def test_agentic_tools_is_none_without_config_files
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_equal "none", result["agentic_tools"]
  end

  def test_description_extracts_from_readme
    readme_content = <<~MD
      # Test Project

      This is a test project for unit testing.

      ## Features

      - Feature 1
      - Feature 2
    MD
    File.write(File.join(@repo_dir, "README.md"), readme_content)
    git_add_commit("Add README")

    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert result["description"]
    assert_includes result["description"], "test project"
  end

  def test_documentation_links_extracts_urls_from_readme
    readme_content = <<~MD
      # Test Project

      Check out our [documentation](https://docs.example.com).
    MD
    File.write(File.join(@repo_dir, "README.md"), readme_content)
    git_add_commit("Add README with link")

    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_kind_of Array, result["documentation_links"]
    urls = result["documentation_links"].map { |l| l["url"] }

    assert_includes urls, "https://docs.example.com"
  end

  def test_bot_commits_are_excluded
    # Add a bot commit
    run_git("git", "-c", "user.name=dependabot[bot]", "-c", "user.email=bot@github.com",
            "commit", "--allow-empty", "-m", "Bot commit")

    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    # Should still be 2 human commits (from setup), not 3
    assert_equal 2, result["commits"]
  end

  def test_commits_per_month_returns_array
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_kind_of Array, result["commits_per_month"]
  end

  def test_contributors_per_month_returns_array
    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_kind_of Array, result["contributors_per_month"]
  end

  def test_recent_tags_returns_array
    run_git("git", "tag", "v1.0.0")

    analytics = Archsight::Import::GitAnalytics.new(@repo_dir)
    result = analytics.analyze

    assert_kind_of Array, result["recent_tags"]
    tag_names = result["recent_tags"].map { |t| t["name"] }

    assert_includes tag_names, "v1.0.0"
  end

  private

  def setup_git_repo
    run_git("git", "init")
    run_git("git", "config", "user.name", "Test User")
    run_git("git", "config", "user.email", "test@example.com")

    # Create initial commit
    File.write(File.join(@repo_dir, "README.md"), "# Test\n")
    run_git("git", "add", ".")
    run_git("git", "commit", "-m", "Initial commit")

    # Create second commit
    File.write(File.join(@repo_dir, "file.txt"), "content\n")
    run_git("git", "add", ".")
    run_git("git", "commit", "-m", "Add file")
  end

  def git_add_commit(message)
    run_git("git", "add", ".")
    run_git("git", "commit", "-m", message)
  end

  def run_git(*)
    system(*, chdir: @repo_dir, out: File::NULL, err: File::NULL)
  end
end
