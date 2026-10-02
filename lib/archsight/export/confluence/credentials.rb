# frozen_string_literal: true

require_relative "../../user_config"

module Archsight
  module Export
    module Confluence
      # What the export needs to know about the Confluence it writes to, from the `confluence` section of the user
      # configuration (see Archsight::UserConfig):
      #
      #   confluence:
      #     token: <personal access token>     # or ARCHSIGHT_CONFLUENCE_TOKEN (CONFLUENCE_TOKEN)
      #     drawio: true                       # this Confluence has the draw.io app (ARCHSIGHT_CONFLUENCE_DRAWIO)
      #
      # The token never appears in output: it is wrapped in a Secret, and the errors name the file and the setting only.
      module Credentials
        TRUE_WORDS = %w[true 1 yes on].freeze

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

        # @param path [String, nil] configuration file (default: see UserConfig.path)
        # @return [Settings]
        # @raise [Archsight::Export::Error] without a token, or with a configuration file that cannot be read
        def load(path: nil, env: ENV)
          file = path ? File.expand_path(path) : UserConfig.path(env: env)
          token = UserConfig.setting("confluence", "token", aliases: ["CONFLUENCE_TOKEN"], env: env, path: path).to_s.strip
          raise Error, missing(file) if token.empty?

          drawio = UserConfig.setting("confluence", "drawio", aliases: ["CONFLUENCE_DRAWIO"], env: env, path: path)
          Settings.new(token: Secret.new(token), drawio: flag(drawio))
        rescue UserConfig::Error => e
          raise Error, e.message
        end

        # "true"/"yes"/... or a YAML boolean; anything else (and unset) is false
        def flag(value)
          value == true || TRUE_WORDS.include?(value.to_s.strip.downcase)
        end

        def missing(file)
          "no Confluence token: set ARCHSIGHT_CONFLUENCE_TOKEN or put `token: <personal access token>` in the `confluence:` section of #{file}"
        end
      end
    end
  end
end
