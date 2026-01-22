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

  def test_import_yaml_generates_correct_structure
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    resource = handler.import_yaml(
      name: "Import:Child",
      handler: "repository",
      config: { "path" => "/test/path" }
    )

    assert_equal "Import", resource["kind"]
    assert_equal "Import:Child", resource["metadata"]["name"]
    assert_equal "repository", resource["metadata"]["annotations"]["import/handler"]
    assert_equal "/test/path", resource["metadata"]["annotations"]["import/config/path"]
    assert_empty(resource["spec"])
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

  def test_resource_yaml_tracks_generated_resources
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    handler.resource_yaml(kind: "TechnologyArtifact", name: "Art:1")
    handler.resource_yaml(kind: "DataObject", name: "Data:1")

    tracked = handler.instance_variable_get(:@tracked_resources)

    assert_equal 2, tracked.size
    assert_equal "TechnologyArtifact", tracked[0][:kind]
    assert_equal "Art:1", tracked[0][:name]
    assert_equal "DataObject", tracked[1][:kind]
    assert_equal "Data:1", tracked[1][:name]
  end

  def test_import_yaml_tracks_generated_imports
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    handler.import_yaml(name: "Import:Child", handler: "repository")

    tracked = handler.instance_variable_get(:@tracked_resources)

    assert_equal 1, tracked.size
    assert_equal "Import", tracked[0][:kind]
    assert_equal "Import:Child", tracked[0][:name]
  end

  def test_generates_meta_record_groups_by_kind
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    handler.resource_yaml(kind: "TechnologyArtifact", name: "Art:1")
    handler.resource_yaml(kind: "TechnologyArtifact", name: "Art:2")
    handler.resource_yaml(kind: "DataObject", name: "Data:1")

    meta = handler.send(:generates_meta_record, handler.instance_variable_get(:@tracked_resources))

    assert_equal "Import", meta["kind"]
    assert_equal "Import:Test", meta["metadata"]["name"]
    assert_equal %w[Art:1 Art:2], meta["spec"]["generates"]["technologyArtifacts"]
    assert_equal ["Data:1"], meta["spec"]["generates"]["dataObjects"]
  end

  def test_write_generates_meta_appends_to_file
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    # First write some initial content
    handler.resource_yaml(kind: "TechnologyArtifact", name: "Art:1")
    handler.write_yaml("---\ntest: content\n")

    # Then write generates meta (should append)
    handler.write_generates_meta

    # Find the written file
    generated_file = File.join(@resources_dir, "generated", "Import_Test.yaml")

    assert_path_exists generated_file, "Expected file to be created at #{generated_file}"

    # Load all YAML documents
    documents = YAML.load_stream(File.read(generated_file))

    assert_equal 2, documents.size, "Expected 2 YAML documents"

    # Second document should be the generates meta
    generates_doc = documents[1]

    assert_equal "Import", generates_doc["kind"]
    assert_equal ["Art:1"], generates_doc["spec"]["generates"]["technologyArtifacts"]
  end

  def test_write_generates_meta_skips_when_empty
    handler = TestHandler.new(@import_resource, database: nil, resources_dir: @resources_dir)

    handler.write_generates_meta

    # Should not create any file when no resources tracked
    generated_file = File.join(@resources_dir, "generated", "Import_Test.yaml")

    refute_path_exists generated_file, "File should not be created when no resources tracked"
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
           :resource_yaml, :import_yaml, :resources_to_yaml,
           :write_generates_meta
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
