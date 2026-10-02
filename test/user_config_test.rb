# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "archsight/user_config"

class UserConfigTest < Minitest::Test
  UserConfig = Archsight::UserConfig

  def with_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "archsight.yaml")
      File.write(path, content) if content
      yield path
    end
  end

  def test_the_default_path_and_the_environment_override
    assert_equal File.expand_path("~/.config/archsight/archsight.yaml"), UserConfig.path(env: {})
    assert_equal File.expand_path("~/.config/archsight/archsight.yaml"), UserConfig.path(env: { "ARCHSIGHT_CONFIG" => "  " })
    assert_equal "/etc/archsight.yaml", UserConfig.path(env: { "ARCHSIGHT_CONFIG" => "/etc/archsight.yaml" })
  end

  def test_a_missing_or_empty_file_is_an_empty_configuration
    with_file(nil) { |path| assert_empty UserConfig.read(path: path) }
    with_file("") { |path| assert_empty UserConfig.read(path: path) }
    with_file("---\n") { |path| assert_empty UserConfig.section("jira", path: path) }
  end

  def test_sections_and_unknown_keys
    with_file("jira:\n  issue_url: https://j.example.com/{issue}\n  future: x\nsomething_else: 1\nconfluence: no\n") do |path|
      assert_equal "https://j.example.com/{issue}", UserConfig.section("jira", path: path)["issue_url"]
      assert_empty UserConfig.section("confluence", path: path)
      assert_empty UserConfig.section("nothing", path: path)
    end
  end

  def test_a_file_that_is_not_a_mapping_or_not_yaml_is_an_error_that_names_the_file_only
    with_file("[a, b]\n") do |path|
      error = assert_raises(UserConfig::Error) { UserConfig.read(path: path) }

      assert_includes error.message, path
    end
    with_file("token: [unclosed\nsecret: hunter2") do |path|
      error = assert_raises(UserConfig::Error) { UserConfig.read(path: path) }

      assert_includes error.message, path
      refute_includes error.message, "hunter2"
    end
  end

  def test_the_environment_alone_is_enough
    assert_equal "from-env", UserConfig.setting("confluence", "token", env: { "ARCHSIGHT_CONFLUENCE_TOKEN" => "from-env", "ARCHSIGHT_CONFIG" => "/no/such/file" })
  end

  def test_the_environment_beats_the_file_and_blank_values_do_not
    with_file("jira:\n  issue_url: from-file\n") do |path|
      assert_equal "from-env", UserConfig.setting("jira", "issue_url", env: { "ARCHSIGHT_JIRA_ISSUE_URL" => "from-env" }, path: path)
      assert_equal "from-file", UserConfig.setting("jira", "issue_url", env: { "ARCHSIGHT_JIRA_ISSUE_URL" => "  " }, path: path)
      assert_equal "from-file", UserConfig.setting("jira", "issue_url", env: {}, path: path)
      assert_nil UserConfig.setting("jira", "token", env: {}, path: path)
    end
  end

  def test_alias_names_work_and_the_main_name_wins
    env = { "CONFLUENCE_TOKEN" => "old-name" }

    assert_equal "old-name", UserConfig.setting("confluence", "token", aliases: ["CONFLUENCE_TOKEN"], env: env, path: "/no/such/file")
    assert_equal "new", UserConfig.setting("confluence", "token", aliases: ["CONFLUENCE_TOKEN"], env: env.merge("ARCHSIGHT_CONFLUENCE_TOKEN" => "new"), path: "/no/such/file")
  end
end
