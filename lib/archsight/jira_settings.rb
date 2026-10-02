# frozen_string_literal: true

require "uri"
require_relative "user_config"

module Archsight
  # Where the issues of Jira live, for `{jira:KEY}` links: the setting `jira.issue_url` (`ARCHSIGHT_JIRA_ISSUE_URL`), a
  # template with `{issue}` for the key, for example `https://jira.example.com/browse/{issue}`. For the Confluence
  # export, whose Jira macro names the Jira server it belongs to, `jira.server` (the name the server has in Confluence)
  # and `jira.server_id` (`ARCHSIGHT_JIRA_SERVER`, `ARCHSIGHT_JIRA_SERVER_ID`). Nothing else of the configuration is
  # read here, a missing or unreadable file means "no links". The host is a setting, never part of the code.
  module JiraSettings
    PLACEHOLDER = "{issue}"

    Values = Struct.new(:issue_url, :server, :server_id)

    @mutex = Mutex.new
    @values = nil

    class << self
      # @return [String, nil] the template, nil unless it is an http(s) URL containing `{issue}`
      def issue_url = values.issue_url

      # @return [String, nil] name of the Jira server in Confluence's Jira macro
      def server = values.server

      # @return [String, nil] id of the Jira server in Confluence's Jira macro
      def server_id = values.server_id

      # @return [String, nil] the link to an issue
      def link_for(key)
        template = issue_url
        template&.sub(PLACEHOLDER) { URI.encode_www_form_component(key) }
      end

      # Forget what was read (tests, or after the file changed)
      def reset!
        @mutex.synchronize { @values = nil }
      end

      private

      def values
        @mutex.synchronize { @values ||= read }
      end

      def read
        setting = lambda do |key|
          value = UserConfig.setting("jira", key).to_s.strip
          value unless value.empty?
        end
        Values.new(usable(setting.call("issue_url")), setting.call("server"), setting.call("server_id"))
      rescue UserConfig::Error
        Values.new(nil, nil, nil)
      end

      def usable(url)
        text = url.to_s.strip
        text if text.match?(%r{\Ahttps?://}) && text.include?(PLACEHOLDER)
      end
    end
  end
end
