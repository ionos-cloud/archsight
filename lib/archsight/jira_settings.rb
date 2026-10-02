# frozen_string_literal: true

require "uri"
require_relative "user_config"

module Archsight
  # Where the issues of Jira live, for `{jira:KEY}` links: the setting `jira.issue_url` (`ARCHSIGHT_JIRA_ISSUE_URL`), a
  # template with `{issue}` for the key, for example `https://jira.example.com/browse/{issue}`. Nothing else of the
  # configuration is read here, a missing or unreadable file means "no links". The host is a setting, never part of
  # the code.
  module JiraSettings
    PLACEHOLDER = "{issue}"

    @mutex = Mutex.new
    @loaded = false
    @issue_url = nil

    class << self
      # @return [String, nil] the template, nil unless it is an http(s) URL containing `{issue}`
      def issue_url
        @mutex.synchronize do
          unless @loaded
            @issue_url = usable(UserConfig.setting("jira", "issue_url"))
            @loaded = true
          end
          @issue_url
        end
      rescue UserConfig::Error
        nil
      end

      # @return [String, nil] the link to an issue
      def link_for(key)
        template = issue_url
        template&.sub(PLACEHOLDER) { URI.encode_www_form_component(key) }
      end

      # Forget what was read (tests, or after the file changed)
      def reset!
        @mutex.synchronize do
          @loaded = false
          @issue_url = nil
        end
      end

      private

      def usable(url)
        text = url.to_s.strip
        text if text.match?(%r{\Ahttps?://}) && text.include?(PLACEHOLDER)
      end
    end
  end
end
