# frozen_string_literal: true

ENV["RACK_ENV"] = "test"
ENV["APP_ENV"] = "test"
# Imports put their cache (clones, the Spotlight marker) here, never in the home directory of the developer
require "tmpdir"
ENV["ARCHSIGHT_IMPORT_CACHE_ROOT"] = File.join(Dir.tmpdir, "archsight-test-cache-#{Process.pid}")

# Suppress warnings from third-party gems (rouge, kramdown)
$VERBOSE = nil

require "simplecov"
SimpleCov.start do
  enable_coverage :branch

  add_filter "/test/"
  add_filter "/examples/"

  add_group "Core", "lib/archsight"
  add_group "Query", "lib/archsight/query"
  add_group "Resources", "lib/archsight/resources"
  add_group "Annotations", "lib/archsight/annotations"
  add_group "MCP", "lib/archsight/mcp"
  add_group "Web", "lib/archsight/web"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "archsight"

require "minitest/autorun"
Minitest.after_run { FileUtils.rm_rf(ENV.fetch("ARCHSIGHT_IMPORT_CACHE_ROOT")) if ENV["ARCHSIGHT_IMPORT_CACHE_ROOT"]&.include?("archsight-test-cache-") }
