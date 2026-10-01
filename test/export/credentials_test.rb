# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "archsight/export"
require "archsight/export/confluence/credentials"

class ConfluenceCredentialsTest < Minitest::Test
  Credentials = Archsight::Export::Confluence::Credentials

  def with_file(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "confluence.yaml")
      File.write(path, content) if content
      yield path
    end
  end

  def test_token_from_the_file
    with_file("token: abc123\n") { |path| assert_equal "abc123", Credentials.load(path: path, env: {}).token.reveal }
  end

  def test_environment_wins
    with_file("token: from-file\n") { |path| assert_equal "from-env", Credentials.load(path: path, env: { "CONFLUENCE_TOKEN" => "from-env" }).token.reveal }
  end

  def test_drawio_flag_defaults_to_false_and_comes_from_the_file_or_the_environment
    with_file("token: t\n") { |path| refute Credentials.load(path: path, env: {}).drawio }
    with_file("token: t\ndrawio: true\n") do |path|
      assert Credentials.load(path: path, env: {}).drawio
      refute Credentials.load(path: path, env: { "CONFLUENCE_DRAWIO" => "false" }).drawio
    end
    with_file("token: t\n") { |path| assert Credentials.load(path: path, env: { "CONFLUENCE_DRAWIO" => "true" }).drawio }
    with_file("token: t\ndrawio: \"yes please\"\n") { |path| refute Credentials.load(path: path, env: {}).drawio }
  end

  def test_an_environment_token_still_reads_the_drawio_flag_of_the_file
    with_file("drawio: true\n") { |path| assert Credentials.load(path: path, env: { "CONFLUENCE_TOKEN" => "t" }).drawio }
  end

  def test_the_secret_never_prints
    secret = Credentials.load(path: nil, env: { "CONFLUENCE_TOKEN" => "abc123" }).token

    refute_includes secret.to_s, "abc123"
    refute_includes secret.inspect, "abc123"
    refute_includes "token=#{secret}", "abc123"
  end

  def test_errors_name_the_file_and_field_but_never_contain_a_token
    with_file(nil) do |path|
      error = assert_raises(Archsight::Export::Error) { Credentials.load(path: path, env: {}) }

      assert_includes error.message, path
      assert_includes error.message, "token:"
    end
    with_file("other: x\n") { |path| assert_includes assert_raises(Archsight::Export::Error) { Credentials.load(path: path, env: {}) }.message, "no `token:` field" }
    with_file("token: [unclosed\n") { |path| assert_includes assert_raises(Archsight::Export::Error) { Credentials.load(path: path, env: {}) }.message, "not valid YAML" }
  end
end
