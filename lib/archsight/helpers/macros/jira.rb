# frozen_string_literal: true

require "erb"
require_relative "../../jira_settings"

module Archsight
  module Helpers
    module Macros
      # `{jira:PROJ-123}`: a Jira issue, like the Jira issue macro of Confluence. The link comes from the
      # `issue_url` setting (see JiraSettings); without it the key is shown as code.
      module Jira
        KEY = /\A[A-Z][A-Z0-9_]+-\d+\z/

        class << self
          # @return [String, nil] the issue key, nil if the arguments are not one
          def parse(arguments)
            key = arguments.to_s.strip
            key if key.match?(KEY)
          end

          def problem(arguments, _context = nil)
            "expected an issue key such as PROJ-123" unless parse(arguments)
          end

          def html(key, _context = nil)
            url = JiraSettings.link_for(key)
            return %(<code class="macro-jira">#{h(key)}</code>) unless url

            %(<a class="macro-jira" href="#{h(url)}" target="_blank" rel="noopener">#{h(key)}</a>)
          end

          # What stands in for the macro where a link of its own is not allowed (inside a link)
          def plain(key) = h(key)

          # The Jira macro of Confluence names its Jira server (`server`, `serverId`); they are added when configured
          def confluence(key, _context = nil)
            parameters = { "server" => JiraSettings.server, "serverId" => JiraSettings.server_id, "key" => key }.compact
            body = parameters.map { |name, value| %(<ac:parameter ac:name="#{name}">#{h(value)}</ac:parameter>) }.join
            %(<ac:structured-macro ac:name="jira">#{body}</ac:structured-macro>)
          end

          private

          def h(text) = ERB::Util.html_escape(text)
        end
      end

      register("jira", Jira)
    end
  end
end
