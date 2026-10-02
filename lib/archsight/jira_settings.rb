# frozen_string_literal: true

require "yaml"
require "uri"

module Archsight
  # Where the issues of Jira live, for `{jira:KEY}` links: the `issue_url` of `~/.config/architecture/jira.yaml`
  # (`ARCHSIGHT_JIRA_CONFIG` names another file), a template with `{issue}` for the key, for example
  # `https://jira.example.com/browse/{issue}`. `ARCHSIGHT_JIRA_ISSUE_URL` overrides the file. Nothing else of the
  # file is read, a missing or unreadable file means "no links". The host is a setting, never part of the code.
  module JiraSettings
    DEFAULT_FILE = "~/.config/architecture/jira.yaml"
    PLACEHOLDER = "{issue}"

    @mutex = Mutex.new
    @loaded = false
    @issue_url = nil

    class << self
      # @return [String, nil] the template, nil unless it is an http(s) URL containing `{issue}`
      def issue_url
        @mutex.synchronize do
          unless @loaded
            @issue_url = usable(ENV["ARCHSIGHT_JIRA_ISSUE_URL"] || from_file)
            @loaded = true
          end
          @issue_url
        end
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

      def from_file
        path = File.expand_path(ENV["ARCHSIGHT_JIRA_CONFIG"] || DEFAULT_FILE)
        return unless File.file?(path)

        settings = YAML.safe_load_file(path)
        settings["issue_url"] if settings.is_a?(Hash)
      rescue Psych::Exception, SystemCallError
        nil
      end

      def usable(url)
        text = url.to_s.strip
        text if text.match?(%r{\Ahttps?://}) && text.include?(PLACEHOLDER)
      end
    end
  end
end
