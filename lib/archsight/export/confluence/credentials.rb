# frozen_string_literal: true

require "yaml"

module Archsight
  module Export
    module Confluence
      # What the export needs to know about the Confluence it writes to, like JIRA_TOKEN for Jira:
      #
      #   ~/.config/architecture/confluence.yaml
      #     token: <personal access token>     # or CONFLUENCE_TOKEN
      #     drawio: true                       # this Confluence has the draw.io app (or CONFLUENCE_DRAWIO=true)
      #
      # The token never appears in output: it is wrapped in a Secret, and the errors name the file and the field only.
      module Credentials
        DEFAULT_PATH = File.join("~", ".config", "architecture", "confluence.yaml")
        TRUE_WORDS = %w[true 1 yes on].freeze
        FALSE_WORDS = %w[false 0 no off].freeze

        # Holds the token; to_s and inspect hide it, #reveal is the one way to read it.
        class Secret
          def initialize(value)
            @value = value
          end

          def reveal = @value
          def to_s = "[FILTERED]"
          alias inspect to_s
        end

        Settings = Struct.new(:token, :drawio, keyword_init: true)

        module_function

        # @param path [String, nil] credentials file (default ~/.config/architecture/confluence.yaml)
        # @return [Settings]
        # @raise [Archsight::Export::Error] without a token
        def load(path: nil, env: ENV)
          file = File.expand_path(path || DEFAULT_PATH)
          data = File.file?(file) ? read(file) : nil
          token = env["CONFLUENCE_TOKEN"].to_s.strip
          token = data["token"].to_s.strip if token.empty? && data
          raise Error, missing(file, data ? "it has no `token:` field" : "the file does not exist") if token.empty?

          Settings.new(token: Secret.new(token), drawio: flag(env["CONFLUENCE_DRAWIO"], data&.fetch("drawio", nil)))
        end

        def read(file)
          data = YAML.safe_load_file(file)
          data.is_a?(Hash) ? data : {}
        rescue Psych::Exception
          raise Error, missing(file, "it is not valid YAML")
        end

        # An environment value ("true"/"false") wins over the file's boolean; unset means false
        def flag(from_env, from_file)
          word = from_env.to_s.strip.downcase
          return true if TRUE_WORDS.include?(word)
          return false if FALSE_WORDS.include?(word)

          from_file == true || TRUE_WORDS.include?(from_file.to_s.downcase)
        end

        def missing(file, reason)
          "no Confluence token: set CONFLUENCE_TOKEN or put `token: <personal access token>` in #{file} (#{reason})"
        end
      end
    end
  end
end
