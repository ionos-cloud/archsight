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

  def test_get_api_kinds_kind_output_annotations
    get "/api/v1/kinds/TechnologyArtifact", output: "annotations", limit: 5

    assert_predicate last_response, :ok?
    data = json_response

    # Annotations output should have name and metadata but no spec
    resource = data["instances"].first

    assert resource["name"]
    assert resource["metadata"]
    assert resource["metadata"]["annotations"]
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

  def test_get_instance_renders_the_diagram_annotation
    get "/api/v1/kinds/BusinessProduct/instances/Archsight"

    assert_predicate last_response, :ok?
    data = json_response

    assert_includes data["diagram"], '<figure class="asd-diagram"><svg'
    assert_includes data["diagram"], 'href="/kinds/ApplicationService/instances/Archsight:Web"'
    refute_includes data["diagram"], 'class="asd-broken-link"'
    # the raw source stays available (the editor and MCP read it)
    assert_includes data["metadata"]["annotations"]["architecture/diagram"], 'theme "compact"'
  end

  def test_get_instance_without_a_diagram_annotation_has_no_diagram
    name = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact").values.first.name
    get "/api/v1/kinds/TechnologyArtifact/instances/#{name}"

    assert_predicate last_response, :ok?
    assert_nil json_response["diagram"]
  end

  def render_diagram(source)
    post "/api/v1/diagrams/render", JSON.generate({ source: source }), "CONTENT_TYPE" => "application/json"
  end

  def test_render_diagram_returns_the_svg
    render_diagram(%(component "a" { label "A" }\n))

    assert_predicate last_response, :ok?
    assert_nil json_response["error"]
    assert_includes json_response["html"], "<svg"
  end

  def test_render_diagram_resolves_resource_references_against_the_database
    render_diagram(%(component "web" { resource "ApplicationComponent/Archsight:Web:API" }\n))

    assert_includes json_response["html"], 'href="/kinds/ApplicationComponent/instances/Archsight:Web:API"'
  end

  def test_render_diagram_reports_a_broken_diagram_as_data_not_as_an_http_error
    render_diagram("not valid ((\n")

    assert_predicate last_response, :ok?
    assert_nil json_response["html"]
    assert_match(/line 1/, json_response["error"])
  end

  def test_render_diagram_rejects_a_body_without_a_source
    post "/api/v1/diagrams/render", "not json", "CONTENT_TYPE" => "application/json"

    assert_equal 400, last_response.status

    post "/api/v1/diagrams/render", JSON.generate({ source: 1 }), "CONTENT_TYPE" => "application/json"

    assert_equal 400, last_response.status
    assert_equal "BadRequest", json_response["error"]
  end

  def test_render_diagram_rejects_an_oversized_source
    render_diagram("#" * 100_001)

    assert_equal 413, last_response.status
  end

  def test_get_instance_with_a_broken_diagram_shows_the_error_box
    instance = Archsight::Web::Application.database.instance_by_kind("BusinessProduct", "Archsight")
    original = instance.annotations["architecture/diagram"]
    instance.annotations["architecture/diagram"] = "not valid ((\n"
    get "/api/v1/kinds/BusinessProduct/instances/Archsight"

    assert_predicate last_response, :ok?
    assert_includes json_response["diagram"], "asd-diagram-error"
  ensure
    instance.annotations["architecture/diagram"] = original
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

  def test_get_api_search_invalid_regex_is_a_bad_request_not_a_server_error
    ['name =~ "["', 'Page: page/content =~ "(unclosed"'].each do |query|
      get "/api/v1/search", q: query

      assert_equal 400, last_response.status, query
      assert_equal "QueryError", json_response["error"]
      assert_includes json_response["message"], "Invalid regular expression"
    end
  end

  def test_get_api_search_regex_literal
    get "/api/v1/search", q: "name =~ /^archsight$/i"

    assert_predicate last_response, :ok?
    assert_includes json_response["instances"].map { |i| i["name"] }, "Archsight"
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

  def test_get_api_search_output_annotations
    get "/api/v1/search", q: 'name =~ ".*"', output: "annotations", limit: 5

    assert_predicate last_response, :ok?
    data = json_response

    # Annotations output should have name and metadata but no spec
    resource = data["instances"].first

    assert resource["name"]
    assert resource["metadata"]
    assert resource["metadata"]["annotations"]
    assert_nil resource["spec"]
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

    # Kind is always included for frontend routing
    resource = data["instances"].first

    assert resource["name"]
    assert_equal "TechnologyArtifact", resource["kind"]
  end

  # GET /api/v1/openapi.yaml tests

  def test_get_openapi_spec
    get "/api/v1/openapi.yaml"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/yaml"
    assert_includes last_response.body, "openapi:"
    assert_includes last_response.body, "Archsight API"
  end

  # GET /docs/api tests

  def test_get_api_docs
    get "/docs/api"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "text/html"
    assert_includes last_response.body, "html"
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

  # POST /api/v1/kinds/Analysis/instances/:name/execute tests

  def test_execute_analysis
    analyses = Archsight::Web::Application.database.instances_by_kind("Analysis")
    skip("No Analysis instances") if analyses.empty?

    name = analyses.keys.first
    post "/api/v1/kinds/Analysis/instances/#{name}/execute"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = json_response

    assert_equal name, data["name"]
    assert_includes [true, false], data["success"]
    assert_kind_of Array, data["sections"]

    if data["sections"].any? # rubocop:disable Style/GuardClause
      section = data["sections"].first

      assert section["type"], "Section must have a type"
    end
  end

  def test_execute_analysis_not_found
    post "/api/v1/kinds/Analysis/instances/nonexistent_analysis_xyz/execute"

    assert_equal 404, last_response.status
    assert_includes last_response.content_type, "application/json"

    data = json_response

    assert_equal "NotFound", data["error"]
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

  # GET /api/v1/status tests

  def test_status_lozenge_is_a_cached_svg
    get "/api/v1/status/yellow/WIP.svg"

    assert_predicate last_response, :ok?
    assert_equal "image/svg+xml", last_response.content_type.split(";").first
    assert_includes last_response.body, ">WIP</text>"
    assert_includes last_response.headers["Cache-Control"], "immutable"
    assert_includes last_response.headers["Cache-Control"], "max-age=31536000"
    assert_equal "nosniff", last_response.headers["X-Content-Type-Options"]
    assert_includes last_response.headers["Content-Security-Policy"], "default-src 'none'"
  end

  def test_status_lozenge_answers_not_modified_for_its_etag
    get "/api/v1/status/green/OK"
    etag = last_response.headers["ETag"]

    refute_nil etag

    get "/api/v1/status/green/OK", {}, { "HTTP_IF_NONE_MATCH" => etag }

    assert_equal 304, last_response.status
  end

  def test_status_lozenge_text_may_be_encoded_and_the_suffix_is_optional
    get "/api/v1/status/red/a%2Fb%20c.svg"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, ">A/B C</text>"
  end

  def test_status_lozenge_rejects_unknown_colours_and_bad_text
    get "/api/v1/status/pink/x"

    assert_equal 404, last_response.status

    get "/api/v1/status/red/#{"a" * 41}"

    assert_equal 400, last_response.status
  end

  # GET /api/v1/requirements tests

  def test_get_api_requirements
    get "/api/v1/requirements", of: "BusinessProcess:"

    assert_predicate last_response, :ok?

    data = json_response

    assert_equal "BusinessProcess:", data["query"]
    assert_equal data["requirements"].length, data["total"]
    assert_predicate data["total"], :positive?
    requirement = data["requirements"].first

    assert_equal "implemented", requirement["status"]
    assert_equal "BusinessProcess", requirement["by"].first["kind"]
    assert_kind_of Float, data["query_time_ms"].to_f
  end

  def test_get_api_requirements_filters
    get "/api/v1/requirements", of: "BusinessProcess:", priority: "must"

    assert_predicate last_response, :ok?
    assert_predicate json_response["total"], :positive?
    assert_equal ["must"], json_response["requirements"].map { |r| r["priority"] }.uniq

    get "/api/v1/requirements", of: "BusinessProcess:", priority: "may", status: "planned"

    assert_predicate last_response, :ok?
    assert_equal 0, json_response["total"]
  end

  def test_get_api_requirements_needs_a_valid_query_and_values
    get "/api/v1/requirements"

    assert_equal 400, last_response.status

    get "/api/v1/requirements", of: "BusinessProcess: ((("

    assert_equal 400, last_response.status
    assert_equal "QueryError", json_response["error"]

    get "/api/v1/requirements", of: "BusinessProcess:", priority: "urgent"

    assert_equal 400, last_response.status
    assert_includes json_response["message"], "priority"

    get "/api/v1/requirements", of: "BusinessProcess:", status: "done"

    assert_equal 400, last_response.status
  end
end
