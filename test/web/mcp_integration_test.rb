# frozen_string_literal: true

require "test_helper"
require "rack/test"
require "archsight/web/application"
require "json"

class McpIntegrationTest < Minitest::Test
  include Rack::Test::Methods

  # Headers required for MCP requests (FastMcp validates Origin for security)
  MCP_HEADERS = {
    "CONTENT_TYPE" => "application/json",
    "HTTP_ORIGIN" => "localhost"
  }.freeze

  def app
    Archsight::Web::Application
  end

  def setup
    Archsight.resources_dir = File.expand_path("../../examples/archsight", __dir__)
    # Ensure MCP is set up
    Archsight::Web::Application.setup_mcp!
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
  end

  # Test that MCP endpoint exists and is handled by FastMcp (not Sinatra 404)
  def test_mcp_messages_endpoint_exists
    post "/mcp/messages", {}.to_json, MCP_HEADERS

    # Should not be Sinatra's 404 page
    refute_includes last_response.body, "Sinatra doesn't know this ditty"
    # FastMcp handles the request (returns 200 even if response is empty due to SSE model)
    assert_equal 200, last_response.status
  end

  def test_mcp_sse_endpoint_exists
    get "/mcp/sse", {}, { "HTTP_ORIGIN" => "localhost" }

    # SSE endpoint should return 200 (streaming response in real server)
    refute_equal 404, last_response.status
    refute_includes last_response.body, "Sinatra doesn't know this ditty"
  end

  def test_mcp_unknown_path_returns_not_found
    post "/mcp/unknown", {}.to_json, MCP_HEADERS

    # Unknown MCP subpaths should return 404 from FastMcp
    response = JSON.parse(last_response.body)

    assert_equal 404, last_response.status
    assert response.key?("error")
    assert_equal(-32_601, response["error"]["code"])
  end

  def test_mcp_origin_validation
    # Without proper origin header, should be forbidden
    post "/mcp/messages", {}.to_json, { "CONTENT_TYPE" => "application/json" }

    assert_equal 403, last_response.status
    response = JSON.parse(last_response.body)

    assert response.key?("error")
    assert_match(/Origin validation failed/, response["error"]["message"])
  end

  def test_setup_mcp_registers_tools
    # Verify setup_mcp! registers the expected tools
    # We can verify this indirectly by checking the MCP module has database set
    refute_nil Archsight::MCP.db
    assert_kind_of Archsight::Database, Archsight::MCP.db
  end

  def test_setup_mcp_can_be_called_multiple_times
    # Should not raise when called multiple times
    Archsight::Web::Application.setup_mcp!
    Archsight::Web::Application.setup_mcp!
    # If we got here without exception, verify db is still set
    refute_nil Archsight::MCP.db
  end
end

# Direct tool tests via MCP module (not HTTP) for coverage
class McpToolsDirectTest < Minitest::Test
  def setup
    Archsight.resources_dir = File.expand_path("../../examples/archsight", __dir__)
    @db = Archsight::Database.new(Archsight.resources_dir)
    @db.reload!
    Archsight::MCP.db = @db
  end

  def teardown
    Archsight::MCP.db = nil
  end

  # Helper to call tool and get result
  def call_tool(tool_class, **args)
    tool = tool_class.new
    result, _meta = tool.call_with_schema_validation!(**args)
    JSON.parse(result)
  end

  def test_query_tool_with_real_database
    result = call_tool(Archsight::MCP::QueryTool, query: "TechnologyArtifact:", limit: 5)

    assert result.key?("total")
    assert result.key?("resources")
    assert_operator result["total"], :>=, 0
  end

  def test_query_tool_brief_output_with_real_database
    result = call_tool(Archsight::MCP::QueryTool, query: "TechnologyArtifact:", output: "brief", limit: 5)

    assert result.key?("resources")
    skip("No resources found") if result["resources"].empty?

    resource = result["resources"].first

    assert resource.key?("name")
    refute resource.key?("description")
  end

  def test_query_tool_count_output_with_real_database
    result = call_tool(Archsight::MCP::QueryTool, query: "TechnologyArtifact:", output: "count")

    assert result.key?("total")
    assert result.key?("by_kind")
    refute result.key?("resources")
  end

  def test_analyze_resource_tool_with_real_database
    # Get a real resource name
    artifacts = @db.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    name = artifacts.keys.first
    result = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "TechnologyArtifact", name: name)

    assert_equal "TechnologyArtifact", result["kind"]
    assert_equal name, result["name"]
    assert result.key?("annotations")
  end

  def test_resource_doc_tool_list_kinds
    result = call_tool(Archsight::MCP::ResourceDocTool)

    assert result.key?("resource_kinds")
    kinds = result["resource_kinds"].map { |k| k["kind"] }

    assert_includes kinds, "TechnologyArtifact"
    assert_includes kinds, "ApplicationComponent"
  end

  def test_resource_doc_tool_specific_kind
    result = call_tool(Archsight::MCP::ResourceDocTool, kind: "TechnologyArtifact")

    assert_equal "TechnologyArtifact", result["kind"]
    assert result.key?("documentation")
    assert_includes result["documentation"], "TechnologyArtifact"
  end
end
