# frozen_string_literal: true

module Archsight
  class Configuration
    attr_accessor :resources_dir, :verbose, :verify, :compute_annotations

    def initialize
      @resources_dir = ENV["ARCHSIGHT_RESOURCES_DIR"] || Dir.pwd
      @verbose = true
      @verify = true
      @compute_annotations = true
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def resources_dir
      configuration.resources_dir
    end

    def resources_dir=(path)
      configuration.resources_dir = File.absolute_path(path)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
