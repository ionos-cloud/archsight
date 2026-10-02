# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "archsight/export"
require "archsight/export/confluence/credentials"

class ConfluenceCredentialsTest < Minitest::Test
  Credentials = Archsight::Export::Confluence::Credentials

  def with_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "archsight.yaml")
      File.write(path, content) if content
      yield path
    end
  end

  def config(token: "token-123", extra: "")
    "confluence:\n  token: #{token}\n#{extra}"
  end

  def test_token_from_the_confluence_section_of_the_file
    with_file(config(token: "abc123")) { |path| assert_equal "abc123", Credentials.load(path: path, env: {}).token.reveal }
  end

  def test_the_environment_is_a_full_alternative_to_the_file
    assert_equal "from-env", Credentials.load(path: "/no/such/file", env: { "ARCHSIGHT_CONFLUENCE_TOKEN" => "from-env" }).token.reveal
    assert_equal "old-name", Credentials.load(path: "/no/such/file", env: { "CONFLUENCE_TOKEN" => "old-name" }).token.reveal
  end

  def test_the_environment_wins_over_the_file
    with_file(config(token: "from-file")) do |path|
      assert_equal "from-env", Credentials.load(path: path, env: { "ARCHSIGHT_CONFLUENCE_TOKEN" => "from-env" }).token.reveal
    end
  end

  def test_drawio_flag_defaults_to_false_and_comes_from_the_file_or_the_environment
    with_file(config) { |path| refute Credentials.load(path: path, env: {}).drawio }
    with_file(config(extra: "  drawio: true\n")) do |path|
      assert Credentials.load(path: path, env: {}).drawio
      refute Credentials.load(path: path, env: { "ARCHSIGHT_CONFLUENCE_DRAWIO" => "false" }).drawio
      refute Credentials.load(path: path, env: { "CONFLUENCE_DRAWIO" => "false" }).drawio
    end
    with_file(config) { |path| assert Credentials.load(path: path, env: { "ARCHSIGHT_CONFLUENCE_DRAWIO" => "true" }).drawio }
    with_file(config(extra: "  drawio: \"yes please\"\n")) { |path| refute Credentials.load(path: path, env: {}).drawio }
  end

  def test_an_environment_token_still_reads_the_drawio_flag_of_the_file
    with_file("confluence:\n  drawio: true\n") { |path| assert Credentials.load(path: path, env: { "ARCHSIGHT_CONFLUENCE_TOKEN" => "t" }).drawio }
  end

  def test_other_sections_and_keys_are_ignored
    with_file("jira:\n  token: not-for-confluence\nconfluence:\n  token: mine\n  future: x\n") do |path|
      assert_equal "mine", Credentials.load(path: path, env: {}).token.reveal
    end
  end

  def test_the_secret_never_prints
    secret = Credentials.load(path: nil, env: { "ARCHSIGHT_CONFLUENCE_TOKEN" => "abc123" }).token

    refute_includes secret.to_s, "abc123"
    refute_includes secret.inspect, "abc123"
    refute_includes "token=#{secret}", "abc123"
  end

  def test_errors_name_the_file_and_setting_but_never_contain_a_token
    with_file(nil) do |path|
      error = assert_raises(Archsight::Export::Error) { Credentials.load(path: path, env: {}) }

      assert_includes error.message, path
      assert_includes error.message, "ARCHSIGHT_CONFLUENCE_TOKEN"
    end
    with_file("jira:\n  token: other\n") { |path| assert_includes assert_raises(Archsight::Export::Error) { Credentials.load(path: path, env: {}) }.message, "no Confluence token" }
    with_file("confluence:\n  token: [unclosed\n  hunter2") do |path|
      message = assert_raises(Archsight::Export::Error) { Credentials.load(path: path, env: {}) }.message

      assert_includes message, "not valid YAML"
      refute_includes message, "hunter2"
    end
  end
end
