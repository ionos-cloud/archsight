# frozen_string_literal: true

require_relative "../../test_helper"
require "tmpdir"
require "archsight/helpers"

class JiraMacroTest < Minitest::Test
  Macros = Archsight::Helpers::Macros
  Settings = Archsight::JiraSettings
  TEMPLATE = "https://jira.example.com/browse/{issue}"

  def setup
    @env = ENV.to_h.slice("ARCHSIGHT_JIRA_ISSUE_URL", "ARCHSIGHT_JIRA_CONFIG")
    ENV.delete("ARCHSIGHT_JIRA_ISSUE_URL")
    ENV["ARCHSIGHT_JIRA_CONFIG"] = File.join(Dir.tmpdir, "no-such-jira-#{Process.pid}.yaml")
    Settings.reset!
  end

  def teardown
    %w[ARCHSIGHT_JIRA_ISSUE_URL ARCHSIGHT_JIRA_CONFIG].each { |key| ENV.delete(key) }
    ENV.update(@env)
    Settings.reset!
  end

  def with_url(url)
    ENV["ARCHSIGHT_JIRA_ISSUE_URL"] = url
    Settings.reset!
  end

  def test_the_key_links_to_the_configured_issue_url
    with_url(TEMPLATE)

    assert_equal %(<a class="macro-jira" href="https://jira.example.com/browse/PROJ-123" target="_blank" rel="noopener">PROJ-123</a>),
                 Macros.render("{jira:PROJ-123}")
  end

  def test_without_a_url_the_key_is_code
    assert_equal %(<code class="macro-jira">PROJ-123</code>), Macros.render("{jira:PROJ-123}")
  end

  def test_only_http_urls_with_the_placeholder_are_used
    ["javascript:alert({issue})", "https://jira.example.com/browse/", "ftp://x/{issue}", ""].each do |url|
      with_url(url)

      assert_includes Macros.render("{jira:PROJ-1}"), "<code", url
    end
  end

  def test_things_that_are_not_issue_keys_stay_as_written
    with_url(TEMPLATE)

    ["proj-1", "PROJ", "PROJ-", "P-1 x", "PROJ-1a"].each do |key|
      assert_equal "{jira:#{key}}", Macros.render("{jira:#{key}}"), key
    end
  end

  def test_the_url_comes_from_the_file_and_nothing_else_of_it_is_used
    Dir.mktmpdir do |dir|
      file = File.join(dir, "jira.yaml")
      File.write(file, "token: secret\nissue_url: #{TEMPLATE}\n")
      ENV["ARCHSIGHT_JIRA_CONFIG"] = file
      Settings.reset!

      assert_equal TEMPLATE, Settings.issue_url
      assert_equal "https://jira.example.com/browse/AB-9", Settings.link_for("AB-9")
    end
  end

  def test_a_broken_file_means_no_links
    Dir.mktmpdir do |dir|
      file = File.join(dir, "jira.yaml")
      File.write(file, "issue_url: [unclosed\n")
      ENV["ARCHSIGHT_JIRA_CONFIG"] = file
      Settings.reset!

      assert_nil Settings.issue_url
    end
  end

  def test_confluence_jira_macro
    xml = Macros.replace("see {jira:PROJ-123}") { |m, v| m.confluence(v) }

    assert_equal %(see <ac:structured-macro ac:name="jira"><ac:parameter ac:name="key">PROJ-123</ac:parameter></ac:structured-macro>), xml
  end

  def test_the_linter_reports_a_bad_key
    assert_equal ["{jira:oops}: expected an issue key such as PROJ-123"], Macros.problems("{jira:oops} {jira:OK-1}")
  end
end
