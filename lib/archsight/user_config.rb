# frozen_string_literal: true

require "yaml"

module Archsight
  # The settings of the person running Archsight (tokens, URLs of other systems), one file with a section per
  # integration:
  #
  #   ~/.config/archsight/archsight.yaml      (ARCHSIGHT_CONFIG names another file)
  #     confluence:
  #       token: ...
  #       drawio: true
  #     jira:
  #       issue_url: https://jira.example.com/browse/{issue}
  #
  # Every setting can also be given as an environment variable, `ARCHSIGHT_<SECTION>_<KEY>`
  # (`ARCHSIGHT_CONFLUENCE_TOKEN`), which wins over the file; there need not be a file at all. Unknown sections and
  # keys are ignored. Errors name the file, never its content (it holds tokens).
  module UserConfig
    DEFAULT_PATH = File.join("~", ".config", "archsight", "archsight.yaml")

    class Error < StandardError; end

    module_function

    # @return [String] the configuration file: ARCHSIGHT_CONFIG or the default
    def path(env: ENV)
      File.expand_path(env["ARCHSIGHT_CONFIG"].to_s.strip.then { |p| p.empty? ? DEFAULT_PATH : p })
    end

    # @param path [String, nil] file to read instead of #path
    # @return [Hash] the whole file, {} if it does not exist
    # @raise [Error] if the file is not a YAML mapping
    def read(path: nil, env: ENV)
      file = path ? File.expand_path(path) : path(env: env)
      return {} unless File.file?(file)

      data = YAML.safe_load_file(file)
      return {} if data.nil?
      raise Error, "#{file} must contain a YAML mapping with a section per integration" unless data.is_a?(Hash)

      data
    rescue Psych::Exception
      raise Error, "#{file} is not valid YAML"
    end

    # @return [Hash] one section of the file, {} if it is missing or not a mapping
    def section(name, path: nil, env: ENV)
      value = read(path: path, env: env)[name.to_s]
      value.is_a?(Hash) ? value : {}
    end

    # The value of one setting: the environment variable ARCHSIGHT_<SECTION>_<KEY> (then the aliases) if it is set and not
    # blank, else the value in the file, else nil.
    # @param aliases [Array<String>] further environment variable names with the same meaning
    def setting(section, key, aliases: [], env: ENV, path: nil)
      names = ["ARCHSIGHT_#{section}_#{key}".upcase, *aliases]
      from_env = names.map { |name| env[name].to_s.strip }.find { |value| !value.empty? }
      return from_env if from_env

      section(section, path: path, env: env)[key.to_s]
    end
  end
end
