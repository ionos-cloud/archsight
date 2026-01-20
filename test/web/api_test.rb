# frozen_string_literal: true

require "test_helper"
require "rack/test"
require "archsight/web/application"
require "json"

class APITest < Minitest::Test
  include Rack::Test::Methods

  def app
    Archsight::Web::Application
  end

  def setup
    Archsight.resources_dir = File.expand_path("../../examples/archsight", __dir__)
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
  end

  def json_response
    JSON.parse(last_response.body)
  end

  # GET /api/v1/kinds tests

  def test_get_api_kinds
    get "/api/v1/kinds"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = json_response

    assert_kind_of Integer, data["total"]
    assert_kind_of Integer, data["total_instances"]
    assert_kind_of Array, data["kinds"]
    assert_predicate data["total"], :positive?

    # Check structure of kind info
    kind = data["kinds"].first

    assert kind["kind"]
    assert_kind_of Integer, kind["instance_count"]
  end

  def test_get_api_kinds_sorted
    get "/api/v1/kinds"

    data = json_response
    kinds = data["kinds"].map { |k| k["kind"] }

    assert_equal kinds.sort, kinds
  end

  # GET /api/v1/kinds/:kind tests

  def test_get_api_kinds_kind
    get "/api/v1/kinds/TechnologyArtifact"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = json_response

    assert_equal "TechnologyArtifact", data["kind"]
    assert_kind_of Integer, data["total"]
    assert_kind_of Integer, data["limit"]
    assert_kind_of Integer, data["offset"]
    assert_kind_of Integer, data["count"]
    assert_kind_of Array, data["instances"]
  end

  def test_get_api_kinds_kind_not_found
    get "/api/v1/kinds/NonExistentKind"

    assert_equal 404, last_response.status
    data = json_response

    assert_equal "NotFound", data["error"]
    assert_includes data["message"], "NonExistentKind"
  end

  def test_get_api_kinds_kind_pagination
    get "/api/v1/kinds/TechnologyArtifact", limit: 5, offset: 0

    assert_predicate last_response, :ok?
    data = json_response

    assert_equal 5, data["limit"]
    assert_equal 0, data["offset"]
    assert_operator data["count"], :<=, 5
  end

  def test_get_api_kinds_kind_pagination_offset
    get "/api/v1/kinds/TechnologyArtifact", limit: 5, offset: 2

    assert_predicate last_response, :ok?
    data = json_response

    assert_equal 5, data["limit"]
    assert_equal 2, data["offset"]
  end

  def test_get_api_kinds_kind_output_brief
    get "/api/v1/kinds/TechnologyArtifact", output: "brief", limit: 5

    assert_predicate last_response, :ok?
    data = json_response

    # Brief output should have name but no metadata/spec
    resource = data["instances"].first

    assert resource["name"]
    assert_nil resource["metadata"]
    assert_nil resource["spec"]
  end

  def test_get_api_kinds_kind_output_complete
    get "/api/v1/kinds/TechnologyArtifact", output: "complete", limit: 5

    assert_predicate last_response, :ok?
    data = json_response

    # Complete output should have name and metadata
    resource = data["instances"].first

    assert resource["name"]
    assert resource["metadata"]
  end

  def test_get_api_kinds_kind_max_limit
    get "/api/v1/kinds/TechnologyArtifact", limit: 1000

    assert_predicate last_response, :ok?
    data = json_response
    # Should be capped at MAX_LIMIT (500)
    assert_operator data["limit"], :<=, 500
  end

  # GET /api/v1/kinds/:kind/instances/:name tests

  def test_get_api_instance
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    instance_name = artifacts.keys.first
    get "/api/v1/kinds/TechnologyArtifact/instances/#{instance_name}"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = json_response

    assert_equal "TechnologyArtifact", data["kind"]
    assert_equal instance_name, data["name"]
    assert data["metadata"]
    assert data["spec"]
    assert data["relations"]
    assert data["references"]
  end

  def test_get_api_instance_kind_not_found
    get "/api/v1/kinds/NonExistentKind/instances/test"

    assert_equal 404, last_response.status
    data = json_response

    assert_equal "NotFound", data["error"]
  end

  def test_get_api_instance_not_found
    get "/api/v1/kinds/TechnologyArtifact/instances/non-existent-instance-xyz"

    assert_equal 404, last_response.status
    data = json_response

    assert_equal "NotFound", data["error"]
    assert_includes data["message"], "non-existent-instance-xyz"
  end

  # GET /api/v1/search tests

  def test_get_api_search
    get "/api/v1/search", q: 'name =~ ".*"'

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = json_response

    assert data["query"]
    assert_kind_of Integer, data["total"]
    assert_kind_of Numeric, data["query_time_ms"]
    assert_kind_of Array, data["instances"]
  end

  def test_get_api_search_simple_query
    get "/api/v1/search", q: "archsight"

    assert_predicate last_response, :ok?
    data = json_response

    assert_equal "archsight", data["query"]
  end

  def test_get_api_search_missing_query
    get "/api/v1/search"

    assert_equal 400, last_response.status
    data = json_response

    assert_equal "BadRequest", data["error"]
    assert_includes data["message"], "'q'"
  end

  def test_get_api_search_invalid_query
    get "/api/v1/search", q: "invalid query ((("

    assert_equal 400, last_response.status
    data = json_response

    assert_equal "QueryError", data["error"]
    assert data["query"]
  end

  def test_get_api_search_pagination
    get "/api/v1/search", q: 'name =~ ".*"', limit: 10, offset: 5

    assert_predicate last_response, :ok?
    data = json_response

    assert_equal 10, data["limit"]
    assert_equal 5, data["offset"]
    assert_operator data["count"], :<=, 10
  end

  def test_get_api_search_output_count
    get "/api/v1/search", q: 'name =~ ".*"', output: "count"

    assert_predicate last_response, :ok?
    data = json_response

    assert data["query"]
    assert_kind_of Integer, data["total"]
    assert data["by_kind"]
    assert_nil data["instances"]
    assert_nil data["limit"]
    assert_nil data["offset"]
  end

  def test_get_api_search_output_brief
    get "/api/v1/search", q: 'name =~ ".*"', output: "brief", limit: 5

    assert_predicate last_response, :ok?
    data = json_response

    # Brief output should have name but no metadata/spec
    resource = data["instances"].first

    assert resource["name"]
    assert_nil resource["metadata"]
    assert_nil resource["spec"]
  end

  def test_get_api_search_with_kind_filter
    get "/api/v1/search", q: 'TechnologyArtifact: name =~ ".*"', limit: 5

    assert_predicate last_response, :ok?
    data = json_response

    # When filtering by kind, kind should be omitted from results
    resource = data["instances"].first

    assert resource["name"]
    assert_nil resource["kind"]
  end

  # GET /api/v1/openapi.yaml tests

  def test_get_openapi_spec
    get "/api/v1/openapi.yaml"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/yaml"
    assert_includes last_response.body, "openapi:"
    assert_includes last_response.body, "Archsight API"
  end

  # GET /api/docs tests

  def test_get_api_docs
    get "/api/docs"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/html"
    assert_includes last_response.body, "redoc"
    assert_includes last_response.body, "openapi.yaml"
  end

  # Convenience alias tests

  def test_get_all_kinds_json_alias
    get "/kinds.json"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = json_response

    assert_kind_of Integer, data["total"]
    assert_kind_of Array, data["kinds"]
  end

  def test_get_kinds_json_alias
    get "/kinds/TechnologyArtifact.json"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = json_response

    assert_equal "TechnologyArtifact", data["kind"]
    assert_kind_of Array, data["instances"]
  end

  def test_get_instance_json_alias
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    instance_name = artifacts.keys.first
    get "/kinds/TechnologyArtifact/instances/#{instance_name}.json"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = json_response

    assert_equal "TechnologyArtifact", data["kind"]
    assert_equal instance_name, data["name"]
  end

  # Helper tests

  def test_pagination_limits
    # Test that invalid limits are handled
    get "/api/v1/kinds/TechnologyArtifact", limit: 0

    assert_predicate last_response, :ok?
    data = json_response
    # Should be normalized to at least 1
    assert_operator data["limit"], :>=, 1
  end

  def test_pagination_negative_offset
    get "/api/v1/kinds/TechnologyArtifact", offset: -10

    assert_predicate last_response, :ok?
    data = json_response
    # Should be normalized to at least 0
    assert_operator data["offset"], :>=, 0
  end
end
