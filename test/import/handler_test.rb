# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "archsight/import/handler"

class HandlerTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
    @import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:Test",
        "annotations" => {
          "import/handler" => "test",
          "import/config/key1" => "value1",
          "import/config/key2" => "value2"
        }
      },
      "spec" => {}
    }
    @import_resource = create_mock_import(@import_raw)
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  def test_config_returns_value
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    assert_equal "value1", handler.config("key1")
    assert_equal "value2", handler.config("key2")
  end

  def test_config_returns_default
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    assert_nil handler.config("nonexistent")
    assert_equal "default", handler.config("nonexistent", default: "default")
  end

  def test_config_all_returns_hash
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    config = handler.config_all

    assert_equal({ "key1" => "value1", "key2" => "value2" }, config)
  end

  def test_write_yaml_creates_file
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    content = "test: content\n"
    path = handler.write_yaml(content, filename: "test.yaml")

    assert_path_exists path
    assert_equal content, File.read(path)
  end

  def test_resource_yaml_includes_generated_annotations
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    resource = handler.resource_yaml(
      kind: "TechnologyArtifact",
      name: "Test:Resource",
      annotations: { "custom/key" => "value" },
      spec: {}
    )

    assert_equal "architecture/v1alpha1", resource["apiVersion"]
    assert_equal "TechnologyArtifact", resource["kind"]
    assert_equal "Test:Resource", resource["metadata"]["name"]
    assert_equal "value", resource["metadata"]["annotations"]["custom/key"]
    assert_equal "Import:Test", resource["metadata"]["annotations"]["generated/script"]
    assert resource["metadata"]["annotations"]["generated/at"]
  end

  def test_import_yaml_includes_dependencies
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    resource = handler.import_yaml(
      name: "Import:Child",
      handler: "repository",
      config: { "path" => "/test/path" },
      depends_on: ["Import:Test"]
    )

    assert_equal "Import", resource["kind"]
    assert_equal "Import:Child", resource["metadata"]["name"]
    assert_equal "repository", resource["metadata"]["annotations"]["import/handler"]
    assert_equal "/test/path", resource["metadata"]["annotations"]["import/config/path"]
    assert_equal ["Import:Test"], resource["spec"]["dependsOn"]["imports"]
  end

  def test_resources_to_yaml_creates_multi_document_yaml
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    resources = [
      { "kind" => "Test", "name" => "first" },
      { "kind" => "Test", "name" => "second" }
    ]

    yaml = handler.resources_to_yaml(resources)

    assert_includes yaml, "kind: Test"
    assert_includes yaml, "name: first"
    assert_includes yaml, "name: second"
  end

  private

  def create_mock_import(raw)
    MockImport.new(raw)
  end

  # Test handler that exposes protected methods
  class TestHandler < Archsight::Import::Handler
    def execute
      # No-op for testing
    end

    # Expose config and other methods for testing
    public :config, :config_all, :write_yaml,
           :resource_yaml, :import_yaml, :resources_to_yaml
  end

  # Mock import resource for testing
  class MockImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/test.yaml")
    end
  end
end
