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

          def confluence(key, _context = nil)
            %(<ac:structured-macro ac:name="jira"><ac:parameter ac:name="key">#{h(key)}</ac:parameter></ac:structured-macro>)
          end

          private

          def h(text) = ERB::Util.html_escape(text)
        end
      end

      register("jira", Jira)
    end
  end
end
