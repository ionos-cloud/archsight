# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "webmock/minitest"
require "archsight/import/handlers/rest_api"
require "archsight/import/progress"

class RestApiHandlerTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  def test_missing_name_raises_error
    handler = create_handler(name: nil, spec_url: "https://example.com/api.yaml")

    error = assert_raises(RuntimeError) { handler.execute }

    assert_equal "Missing required config: name", error.message
  end

  def test_missing_spec_url_raises_error
    handler = create_handler(name: "compute", spec_url: nil)

    error = assert_raises(RuntimeError) { handler.execute }

    assert_equal "Missing required config: specUrl", error.message
  end

  def test_generates_application_interface
    openapi_yaml = {
      "openapi" => "3.0.3",
      "info" => {
        "title" => "Compute API",
        "description" => "Manage virtual servers"
      },
      "paths" => {},
      "components" => {
        "securitySchemes" => {
          "bearerAuth" => {
            "type" => "http",
            "scheme" => "bearer",
            "bearerFormat" => "JWT"
          }
        },
        "schemas" => {}
      }
    }.to_yaml

    stub_request(:get, "https://example.com/rest-api/compute/openapi.yaml")
      .to_return(status: 200, body: openapi_yaml, headers: { "Content-Type" => "application/yaml" })

    handler = create_handler(
      name: "compute",
      version: "6.0",
      visibility: "private",
      spec_url: "https://example.com/rest-api/compute/openapi.yaml",
      html_url: "https://example.com/rest-api/compute/redoc.html",
      gate: "GA"
    )

    handler.execute

    # Check output file
    output_path = File.join(@resources_dir, "generated", "compute-interface.yaml")

    assert_path_exists output_path

    content = File.read(output_path)
    resource = YAML.safe_load(content)

    assert_equal "ApplicationInterface", resource["kind"]
    assert_equal "Private:Compute:v6:RestAPI", resource["metadata"]["name"]
    assert_equal "Compute API", resource["metadata"]["annotations"]["architecture/title"]
    assert_equal "GA", resource["metadata"]["annotations"]["architecture/status"]
    assert_equal "private", resource["metadata"]["annotations"]["architecture/visibility"]
    assert_includes resource["metadata"]["annotations"]["architecture/tags"], "jwt"
    assert_equal "https://example.com/rest-api/compute/redoc.html",
                 resource["metadata"]["annotations"]["architecture/documentation"]
  end

  def test_detects_basic_auth
    openapi_yaml = {
      "openapi" => "3.0.0",
      "info" => { "title" => "Test API" },
      "paths" => {},
      "components" => {
        "securitySchemes" => {
          "basicAuth" => {
            "type" => "http",
            "scheme" => "basic"
          }
        },
        "schemas" => {}
      }
    }.to_yaml

    stub_request(:get, "https://example.com/api.yaml")
      .to_return(status: 200, body: openapi_yaml)

    handler = create_handler(
      name: "test",
      spec_url: "https://example.com/api.yaml"
    )

    handler.execute

    output_path = File.join(@resources_dir, "generated", "test-interface.yaml")
    content = File.read(output_path)
    resource = YAML.safe_load(content)

    assert_includes resource["metadata"]["annotations"]["architecture/tags"], "basic-auth"
    assert_includes resource["spec"]["servedBy"]["technologyComponents"], "AUTH:Basic"
  end

  def test_detects_api_key_auth
    openapi_yaml = {
      "openapi" => "3.0.0",
      "info" => { "title" => "Test API" },
      "paths" => {},
      "components" => {
        "securitySchemes" => {
          "apiKeyAuth" => {
            "type" => "apiKey",
            "in" => "header",
            "name" => "X-API-Key"
          }
        },
        "schemas" => {}
      }
    }.to_yaml

    stub_request(:get, "https://example.com/api.yaml")
      .to_return(status: 200, body: openapi_yaml)

    handler = create_handler(
      name: "test",
      spec_url: "https://example.com/api.yaml"
    )

    handler.execute

    output_path = File.join(@resources_dir, "generated", "test-interface.yaml")
    content = File.read(output_path)
    resource = YAML.safe_load(content)

    assert_includes resource["metadata"]["annotations"]["architecture/tags"], "api-key"
  end

  def test_generates_data_objects
    openapi_yaml = {
      "openapi" => "3.0.0",
      "info" => { "title" => "Compute API" },
      "paths" => {},
      "components" => {
        "schemas" => {
          "Server" => {
            "type" => "object",
            "description" => "A virtual server instance",
            "properties" => {
              "id" => { "type" => "string", "format" => "uuid", "description" => "Server ID" },
              "name" => { "type" => "string", "description" => "Server name" }
            },
            "required" => ["name"]
          },
          "ServerCreate" => {
            "type" => "object",
            "properties" => {
              "name" => { "type" => "string" },
              "cores" => { "type" => "integer" }
            }
          }
        }
      }
    }.to_yaml

    stub_request(:get, "https://example.com/api.yaml")
      .to_return(status: 200, body: openapi_yaml)

    handler = create_handler(
      name: "compute",
      spec_url: "https://example.com/api.yaml"
    )

    handler.execute

    # Check data objects file
    output_path = File.join(@resources_dir, "generated", "compute-data-objects.yaml")

    assert_path_exists output_path

    content = File.read(output_path)
    resources = YAML.load_stream(content)

    # Should have one DataObject (Server and ServerCreate normalize to same)
    data_objects = resources.select { |r| r["kind"] == "DataObject" }

    assert_equal 1, data_objects.size

    server = data_objects.first

    assert_equal "Compute:Server", server["metadata"]["name"]
    assert_equal "Compute", server["metadata"]["annotations"]["data/application"]
    assert_includes server["metadata"]["annotations"]["generated/variants"], "Server"
    assert_includes server["metadata"]["annotations"]["generated/variants"], "ServerCreate"
  end

  def test_handles_http_errors
    stub_request(:get, "https://example.com/api.yaml")
      .to_return(status: 404, body: "Not Found")

    handler = create_handler(
      name: "test",
      spec_url: "https://example.com/api.yaml"
    )

    error = assert_raises(RuntimeError) { handler.execute }

    assert_includes error.message, "404"
  end

  def test_follows_redirects
    openapi_yaml = {
      "openapi" => "3.0.0",
      "info" => { "title" => "Test API" },
      "paths" => {},
      "components" => { "schemas" => {} }
    }.to_yaml

    stub_request(:get, "https://example.com/api.yaml")
      .to_return(status: 302, headers: { "Location" => "https://example.com/v2/api.yaml" })

    stub_request(:get, "https://example.com/v2/api.yaml")
      .to_return(status: 200, body: openapi_yaml)

    handler = create_handler(
      name: "test",
      spec_url: "https://example.com/api.yaml"
    )

    # Should not raise
    handler.execute
  end

  def test_builds_interface_name_correctly
    openapi_yaml = {
      "openapi" => "3.0.0",
      "info" => { "title" => "Test API" },
      "paths" => {},
      "components" => { "schemas" => {} }
    }.to_yaml

    stub_request(:get, "https://example.com/api.yaml")
      .to_return(status: 200, body: openapi_yaml)

    handler = create_handler(
      name: "cloud-compute",
      version: "2.1",
      visibility: "public-preview",
      spec_url: "https://example.com/api.yaml"
    )

    handler.execute

    output_path = File.join(@resources_dir, "generated", "cloud-compute-interface.yaml")
    content = File.read(output_path)
    resource = YAML.safe_load(content)

    assert_equal "PublicPreview:CloudCompute:v2:RestAPI", resource["metadata"]["name"]
  end

  def test_handles_version_with_v_prefix
    openapi_yaml = {
      "openapi" => "3.0.0",
      "info" => { "title" => "Test API" },
      "paths" => {},
      "components" => { "schemas" => {} }
    }.to_yaml

    stub_request(:get, "https://example.com/api.yaml")
      .to_return(status: 200, body: openapi_yaml)

    handler = create_handler(
      name: "access-check",
      version: "v1",
      visibility: "private",
      spec_url: "https://example.com/api.yaml"
    )

    handler.execute

    output_path = File.join(@resources_dir, "generated", "access-check-interface.yaml")
    content = File.read(output_path)
    resource = YAML.safe_load(content)

    # Should be "v1", not "vv1"
    assert_equal "Private:AccessCheck:v1:RestAPI", resource["metadata"]["name"]
  end

  def test_reads_from_file_url
    # Create a temp file with OpenAPI spec
    openapi_yaml = {
      "openapi" => "3.0.0",
      "info" => { "title" => "File Test API" },
      "paths" => {},
      "components" => { "schemas" => {} }
    }.to_yaml

    spec_file = File.join(@resources_dir, "spec.yaml")
    File.write(spec_file, openapi_yaml)

    handler = create_handler(
      name: "test",
      spec_url: "file://#{spec_file}"
    )

    handler.execute

    output_path = File.join(@resources_dir, "generated", "test-interface.yaml")

    assert_path_exists output_path

    content = File.read(output_path)
    resource = YAML.safe_load(content)

    assert_equal "File Test API", resource["metadata"]["annotations"]["architecture/title"]
  end

  def test_unsupported_url_scheme_raises_error
    handler = create_handler(
      name: "test",
      spec_url: "ftp://example.com/api.yaml"
    )

    error = assert_raises(RuntimeError) { handler.execute }

    assert_includes error.message, "Unsupported URL scheme"
  end

  private

  def create_handler(name:, spec_url:, version: "1.0", visibility: "private",
                     html_url: nil, gate: "GA")
    annotations = {
      "import/handler" => "rest-api"
    }
    annotations["import/config/name"] = name if name
    annotations["import/config/version"] = version
    annotations["import/config/visibility"] = visibility
    annotations["import/config/specUrl"] = spec_url if spec_url
    annotations["import/config/htmlUrl"] = html_url if html_url
    annotations["import/config/gate"] = gate

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:RestApi:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockRestApiImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::RestApi.new(import_resource, database: nil, resources_dir: @resources_dir,
                                                              progress: progress)
  end

  # Mock import resource for testing
  class MockRestApiImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/rest-api-test.yaml")
    end
  end
end
