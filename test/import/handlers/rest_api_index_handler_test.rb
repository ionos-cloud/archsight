# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "webmock/minitest"
require "archsight/import/handlers/rest_api_index"
require "archsight/import/progress"

class RestApiIndexHandlerTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  def test_missing_index_url_raises_error
    handler = create_handler(index_url: nil)

    error = assert_raises(RuntimeError) { handler.execute }

    assert_equal "Missing required config: indexUrl", error.message
  end

  def test_fetches_index_and_generates_imports
    index_json = [
      {
        "name" => "compute",
        "version" => "6.0",
        "visibility" => "private",
        "specPath" => "/rest-api/compute/openapi.yaml",
        "redocPath" => "/rest-api/compute/redoc.html",
        "gate" => "GA"
      },
      {
        "name" => "storage",
        "version" => "2.0",
        "visibility" => "private",
        "specPath" => "/rest-api/storage/openapi.yaml",
        "gate" => "BETA"
      }
    ].to_json

    stub_request(:get, "https://example.com/api-index.json")
      .to_return(status: 200, body: index_json, headers: { "Content-Type" => "application/json" })

    handler = create_handler(
      index_url: "https://example.com/api-index.json",
      interface_output_path: "generated/interfaces.yaml",
      data_object_output_path: "generated/data-objects.yaml"
    )

    handler.execute

    # Check output file
    output_path = File.join(@resources_dir, "generated", "Import_RestApi_Index.yaml")

    assert_path_exists output_path

    content = File.read(output_path)
    resources = YAML.load_stream(content)

    # Should have 2 child imports + 1 self marker
    imports = resources.select { |r| r["kind"] == "Import" }

    assert_equal 3, imports.size

    # Check compute import - should have full URLs now
    compute_import = imports.find { |r| r["metadata"]["name"] == "Import:RestApi:compute" }

    refute_nil compute_import
    assert_equal "rest-api", compute_import["metadata"]["annotations"]["import/handler"]
    assert_equal "compute", compute_import["metadata"]["annotations"]["import/config/name"]
    assert_equal "6.0", compute_import["metadata"]["annotations"]["import/config/version"]
    assert_equal "private", compute_import["metadata"]["annotations"]["import/config/visibility"]
    assert_equal "https://example.com/rest-api/compute/openapi.yaml",
                 compute_import["metadata"]["annotations"]["import/config/specUrl"]
    assert_equal "https://example.com/rest-api/compute/redoc.html",
                 compute_import["metadata"]["annotations"]["import/config/htmlUrl"]
    assert_equal "GA", compute_import["metadata"]["annotations"]["import/config/gate"]
    assert_equal ["Import:RestApi:Index"], compute_import["spec"]["dependsOn"]["imports"]

    # Check storage import (no htmlUrl)
    storage_import = imports.find { |r| r["metadata"]["name"] == "Import:RestApi:storage" }

    refute_nil storage_import
    assert_nil storage_import["metadata"]["annotations"]["import/config/htmlUrl"]
    assert_equal "BETA", storage_import["metadata"]["annotations"]["import/config/gate"]
  end

  def test_derives_base_url_from_index_url
    index_json = [
      { "name" => "test", "specPath" => "/api.yaml" }
    ].to_json

    stub_request(:get, "https://api.example.com/v1/index.json")
      .to_return(status: 200, body: index_json)

    handler = create_handler(
      index_url: "https://api.example.com/v1/index.json",
      base_url: nil # Not provided, should be derived
    )

    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_RestApi_Index.yaml")
    content = File.read(output_path)
    resources = YAML.load_stream(content)

    test_import = resources.find { |r| r["metadata"]["name"] == "Import:RestApi:test" }

    # Should build full URL from derived base URL
    assert_equal "https://api.example.com/api.yaml",
                 test_import["metadata"]["annotations"]["import/config/specUrl"]
  end

  def test_uses_explicit_base_url
    index_json = [
      { "name" => "test", "specPath" => "/api.yaml" }
    ].to_json

    stub_request(:get, "https://example.com/index.json")
      .to_return(status: 200, body: index_json)

    handler = create_handler(
      index_url: "https://example.com/index.json",
      base_url: "https://cdn.example.com"
    )

    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_RestApi_Index.yaml")
    content = File.read(output_path)
    resources = YAML.load_stream(content)

    test_import = resources.find { |r| r["metadata"]["name"] == "Import:RestApi:test" }

    # Should build full URL from explicit base URL
    assert_equal "https://cdn.example.com/api.yaml",
                 test_import["metadata"]["annotations"]["import/config/specUrl"]
  end

  def test_skips_apis_by_visibility
    index_json = [
      { "name" => "stable", "visibility" => "private", "specPath" => "/stable.yaml" },
      { "name" => "preview", "visibility" => "public-preview", "specPath" => "/preview.yaml" },
      { "name" => "beta", "visibility" => "beta", "specPath" => "/beta.yaml" }
    ].to_json

    stub_request(:get, "https://example.com/index.json")
      .to_return(status: 200, body: index_json)

    handler = create_handler(
      index_url: "https://example.com/index.json",
      skip_visibility: "public-preview,beta"
    )

    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_RestApi_Index.yaml")
    content = File.read(output_path)
    resources = YAML.load_stream(content)

    import_names = resources.map { |r| r["metadata"]["name"] }

    assert_includes import_names, "Import:RestApi:stable"
    refute_includes import_names, "Import:RestApi:preview"
    refute_includes import_names, "Import:RestApi:beta"
  end

  def test_handles_empty_index
    stub_request(:get, "https://example.com/index.json")
      .to_return(status: 200, body: "[]")

    handler = create_handler(index_url: "https://example.com/index.json")

    # Should not raise, just warn
    handler.execute
  end

  def test_handles_http_errors
    stub_request(:get, "https://example.com/index.json")
      .to_return(status: 404, body: "Not Found")

    handler = create_handler(index_url: "https://example.com/index.json")

    error = assert_raises(RuntimeError) { handler.execute }

    assert_includes error.message, "404"
  end

  def test_handles_unauthorized_error
    stub_request(:get, "https://example.com/index.json")
      .to_return(status: 401, body: "Unauthorized")

    handler = create_handler(index_url: "https://example.com/index.json")

    error = assert_raises(RuntimeError) { handler.execute }

    assert_includes error.message, "401 Unauthorized"
  end

  def test_follows_redirects
    index_json = [{ "name" => "test", "specPath" => "/api.yaml" }].to_json

    stub_request(:get, "https://example.com/index.json")
      .to_return(status: 302, headers: { "Location" => "https://example.com/v2/index.json" })

    stub_request(:get, "https://example.com/v2/index.json")
      .to_return(status: 200, body: index_json)

    handler = create_handler(index_url: "https://example.com/index.json")

    # Should not raise
    handler.execute
  end

  def test_propagates_output_paths_to_child_imports
    index_json = [
      { "name" => "test", "specPath" => "/api.yaml" }
    ].to_json

    stub_request(:get, "https://example.com/index.json")
      .to_return(status: 200, body: index_json)

    handler = create_handler(
      index_url: "https://example.com/index.json",
      interface_output_path: "generated/rest-api-interfaces.yaml",
      data_object_output_path: "generated/rest-api-data-objects.yaml"
    )

    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_RestApi_Index.yaml")
    content = File.read(output_path)
    resources = YAML.load_stream(content)

    test_import = resources.find { |r| r["metadata"]["name"] == "Import:RestApi:test" }

    # Check that paths are propagated to child imports
    assert_equal "generated/rest-api-interfaces.yaml",
                 test_import["metadata"]["annotations"]["import/config/interfaceOutputPath"]
    assert_equal "generated/rest-api-data-objects.yaml",
                 test_import["metadata"]["annotations"]["import/config/dataObjectOutputPath"]
  end

  def test_includes_self_marker
    index_json = [{ "name" => "test", "specPath" => "/api.yaml" }].to_json

    stub_request(:get, "https://example.com/index.json")
      .to_return(status: 200, body: index_json)

    handler = create_handler(index_url: "https://example.com/index.json")
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_RestApi_Index.yaml")
    content = File.read(output_path)
    resources = YAML.load_stream(content)

    # Should include self marker
    self_marker = resources.find { |r| r["metadata"]["name"] == "Import:RestApi:Index" }

    refute_nil self_marker
    assert self_marker["metadata"]["annotations"]["generated/at"]
  end

  def test_preserves_full_urls_in_index
    index_json = [
      {
        "name" => "external",
        "specPath" => "https://other.example.com/api.yaml",
        "redocPath" => "https://docs.example.com/external/"
      }
    ].to_json

    stub_request(:get, "https://example.com/index.json")
      .to_return(status: 200, body: index_json)

    handler = create_handler(index_url: "https://example.com/index.json")
    handler.execute

    output_path = File.join(@resources_dir, "generated", "Import_RestApi_Index.yaml")
    content = File.read(output_path)
    resources = YAML.load_stream(content)

    external_import = resources.find { |r| r["metadata"]["name"] == "Import:RestApi:external" }

    # Full URLs should be preserved as-is
    assert_equal "https://other.example.com/api.yaml",
                 external_import["metadata"]["annotations"]["import/config/specUrl"]
    assert_equal "https://docs.example.com/external/",
                 external_import["metadata"]["annotations"]["import/config/htmlUrl"]
  end

  private

  def create_handler(index_url:, base_url: nil, interface_output_path: nil,
                     data_object_output_path: nil, skip_visibility: nil)
    annotations = {
      "import/handler" => "rest-api-index"
    }
    annotations["import/config/indexUrl"] = index_url if index_url
    annotations["import/config/baseUrl"] = base_url if base_url
    annotations["import/config/interfaceOutputPath"] = interface_output_path if interface_output_path
    annotations["import/config/dataObjectOutputPath"] = data_object_output_path if data_object_output_path
    annotations["import/config/skipVisibility"] = skip_visibility if skip_visibility

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:RestApi:Index",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockRestApiIndexImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::RestApiIndex.new(import_resource, database: nil, resources_dir: @resources_dir,
                                                                   progress: progress)
  end

  # Mock import resource for testing
  class MockRestApiIndexImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/rest-api-index-test.yaml")
    end
  end
end
