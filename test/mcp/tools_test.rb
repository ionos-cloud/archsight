# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/mcp"
require "archsight/analysis"
require "json"

class McpToolsTest < Minitest::Test
  def setup
    @db = MockDatabase.new

    # Create test resources
    @db.add_instance("TechnologyArtifact", "repo-active", {
                       "activity/status" => "active",
                       "repository/artifacts" => "container",
                       "architecture/description" => "Active repository\nWith multiple lines"
                     })
    @db.add_instance("TechnologyArtifact", "repo-abandoned", {
                       "activity/status" => "abandoned",
                       "repository/artifacts" => "binary"
                     })
    @db.add_instance("ApplicationInterface", "Kubernetes:RestAPI", {
                       "activity/status" => "active",
                       "architecture/description" => "Kubernetes REST API interface"
                     })
    @db.add_instance("ApplicationComponent", "MyService", {
                       "activity/status" => "active",
                       "repository/artifacts" => "container"
                     })

    # Set up relations
    @db.link("ApplicationComponent", "MyService", :exposes, :applicationInterfaces, "ApplicationInterface",
             "Kubernetes:RestAPI")
    @db.link("ApplicationComponent", "MyService", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "repo-active")

    # Create test Analysis resources
    @db.add_instance("Analysis", "Analysis:Test:Simple", {
                       "analysis/description" => "A simple test analysis",
                       "analysis/handler" => "ruby",
                       "analysis/timeout" => "10s",
                       "analysis/script" => 'heading("Test Results"); info("Analysis completed")'
                     })
    @db.add_instance("Analysis", "Analysis:Test:NoScript", {
                       "analysis/description" => "Analysis without a script"
                     })
    @db.add_instance("Analysis", "Analysis:Test:Failing", {
                       "analysis/description" => "Analysis that raises an error",
                       "analysis/handler" => "ruby",
                       "analysis/script" => 'raise "Something went wrong"'
                     })

    # Inject mock database
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

  # QueryTool tests
  def test_query_tool_name_search
    result = call_tool(Archsight::MCP::QueryTool, query: "repo")

    assert_equal 2, result["total"]
    names = result["resources"].map { |r| r["name"] }

    assert_includes names, "repo-active"
    assert_includes names, "repo-abandoned"
  end

  def test_query_tool_annotation_filter
    result = call_tool(Archsight::MCP::QueryTool, query: 'activity/status == "active"')

    assert_equal 3, result["total"]
    names = result["resources"].map { |r| r["name"] }

    assert_includes names, "repo-active"
    assert_includes names, "MyService"
    refute_includes names, "repo-abandoned"
  end

  def test_query_tool_kind_filter
    result = call_tool(Archsight::MCP::QueryTool, query: 'TechnologyArtifact: activity/status == "active"')

    assert_equal 1, result["total"]
    assert_equal "repo-active", result["resources"].first["name"]
    # When filtering by a specific kind, the kind field is omitted (it's redundant)
    refute result["resources"].first.key?("kind"), "kind should be omitted when filtering by specific kind"
  end

  def test_query_tool_brief_output
    result = call_tool(Archsight::MCP::QueryTool, query: "repo-active", output: "brief")

    resource = result["resources"].first

    assert_equal "repo-active", resource["name"]
    assert_equal "TechnologyArtifact", resource["kind"]
    refute resource.key?("description")
  end

  def test_query_tool_count_output
    result = call_tool(Archsight::MCP::QueryTool, query: 'activity/status == "active"', output: "count")

    assert_equal 3, result["total"]
    assert result.key?("by_kind")
    assert_equal 1, result["by_kind"]["TechnologyArtifact"]
    assert_equal 1, result["by_kind"]["ApplicationInterface"]
    assert_equal 1, result["by_kind"]["ApplicationComponent"]
    refute result.key?("resources")
  end

  def test_query_tool_pagination
    result = call_tool(Archsight::MCP::QueryTool, query: 'activity/status == "active"', limit: 2, offset: 1)

    assert_equal 3, result["total"]
    assert_equal 2, result["count"]
    assert_equal 2, result["limit"]
    assert_equal 1, result["offset"]
  end

  def test_query_tool_relation_query
    result = call_tool(Archsight::MCP::QueryTool, query: "-> ApplicationInterface")

    names = result["resources"].map { |r| r["name"] }

    assert_includes names, "MyService"
  end

  def test_query_tool_error_handling
    result = call_tool(Archsight::MCP::QueryTool, query: "invalid ==")

    assert result.key?("error")
    assert_equal "Query error", result["error"]
    assert result.key?("message")
    assert result.key?("query")
    assert_equal "invalid ==", result["query"]
  end

  def test_query_tool_syntax_error_shows_position
    result = call_tool(Archsight::MCP::QueryTool, query: 'name == "test" &&& invalid')

    assert result.key?("error")
    assert_equal "Query error", result["error"]
    # Error message should include position indicator
    assert result["message"].include?("^") || result["message"].include?("Expected")
  end

  def test_query_tool_handles_empty_query
    # fast-mcp validates that query must be filled, so empty string raises InvalidArgumentsError
    assert_raises(FastMcp::Tool::InvalidArgumentsError) do
      call_tool(Archsight::MCP::QueryTool, query: "")
    end
  end

  # AnalyzeResourceTool tests
  def test_analyze_resource_tool
    result = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "TechnologyArtifact", name: "repo-active")

    assert_equal "TechnologyArtifact", result["kind"]
    assert_equal "repo-active", result["name"]
    assert_equal "active", result["annotations"]["activity/status"]
  end

  def test_analyze_resource_tool_not_found
    result = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "TechnologyArtifact", name: "nonexistent")

    assert result.key?("error")
    assert_equal "Error", result["error"]
    assert_match(/not found/, result["message"])
  end

  def test_analyze_resource_tool_unknown_kind
    result = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "InvalidKind", name: "test")

    assert result.key?("error")
    assert_equal "Error", result["error"]
    assert_match(/Unknown resource kind/, result["message"])
  end

  def test_analyze_resource_tool_with_depth
    result = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "ApplicationComponent", name: "MyService", depth: 2)

    assert_equal "ApplicationComponent", result["kind"]
    assert_equal "MyService", result["name"]

    # With depth > 0, should have outgoing/incoming instead of relations
    assert result.key?("outgoing")
    assert result.key?("incoming")
    refute result.key?("relations")

    # Check outgoing includes the related resources
    outgoing_names = result["outgoing"].map { |r| r["name"] }

    assert_includes outgoing_names, "Kubernetes:RestAPI"
    assert_includes outgoing_names, "repo-active"
  end

  # Orphan detection via query (replaces FindOrphansTool)
  def test_query_tool_no_incoming_relations
    result = call_tool(Archsight::MCP::QueryTool, query: "<- none")

    # repo-abandoned has no relations, so it has no incoming relations
    names = result["resources"].map { |r| r["name"] }

    assert_includes names, "repo-abandoned"
  end

  def test_query_tool_no_outgoing_relations
    result = call_tool(Archsight::MCP::QueryTool, query: "-> none")

    # Resources with no outgoing relations
    names = result["resources"].map { |r| r["name"] }

    assert_includes names, "repo-abandoned"
    assert_includes names, "repo-active" # TechnologyArtifact has no outgoing relations defined
  end

  def test_query_tool_no_relations_with_kind_filter
    result = call_tool(Archsight::MCP::QueryTool, query: "TechnologyArtifact: <- none")

    # When filtering by a specific kind, the kind field is omitted (it's redundant)
    result["resources"].each do |resource|
      refute resource.key?("kind"), "kind should be omitted when filtering by specific kind"
    end
    # repo-abandoned is not referenced by anything
    names = result["resources"].map { |r| r["name"] }

    assert_includes names, "repo-abandoned"
  end

  def test_query_tool_true_orphan
    result = call_tool(Archsight::MCP::QueryTool, query: "-> none & <- none")

    # repo-abandoned has no relations at all
    names = result["resources"].map { |r| r["name"] }

    assert_includes names, "repo-abandoned"
    # repo-active has incoming (referenced by MyService), so not a true orphan
    refute_includes names, "repo-active"
  end

  # Impact analysis test
  def test_analyze_resource_tool_with_impact
    result = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "ApplicationInterface", name: "Kubernetes:RestAPI",
                                                            impact: true)

    assert_equal "impact", result["analysis"]
    assert_equal "Kubernetes:RestAPI", result["target"]["name"]
    assert result.key?("summary")
    assert result.key?("impacted_resources")

    # MyService depends on Kubernetes:RestAPI, so it should be impacted
    all_impacted = result["impacted_resources"].values.flatten
    impacted_names = all_impacted.map { |r| r["name"] }

    assert_includes impacted_names, "MyService"
  end

  # Additional edge case tests for better coverage

  def test_query_tool_with_complete_output
    result = call_tool(Archsight::MCP::QueryTool, query: "repo-active", output: "complete")

    resource = result["resources"].first

    assert_equal "repo-active", resource["name"]
    # Complete output includes more fields than brief
    assert_equal "TechnologyArtifact", resource["kind"]
  end

  def test_query_tool_with_offset
    result = call_tool(Archsight::MCP::QueryTool, query: 'activity/status == "active"', limit: 1, offset: 0)

    assert_equal 3, result["total"]
    assert_equal 1, result["count"]
    assert_equal 0, result["offset"]
  end

  def test_analyze_resource_tool_with_group_by_kind
    result = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "ApplicationComponent", name: "MyService",
                                                            depth: 1, group_by: "kind")

    assert_equal "ApplicationComponent", result["kind"]
    assert result.key?("outgoing") || result.key?("incoming")
  end

  def test_analyze_resource_tool_with_group_by_verb
    result = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "ApplicationComponent", name: "MyService",
                                                            depth: 1, group_by: "verb")

    assert_equal "ApplicationComponent", result["kind"]
    assert result.key?("outgoing") || result.key?("incoming")
  end

  def test_query_tool_sub_query
    result = call_tool(Archsight::MCP::QueryTool, query: "-> $(ApplicationInterface:)")

    # Should return resources that have relations to ApplicationInterface
    assert result.key?("total")
    assert result.key?("resources")
  end

  def test_resource_doc_tool_unknown_kind
    result = call_tool(Archsight::MCP::ResourceDocTool, kind: "UnknownKind")

    assert result.key?("error")
    assert_match(/Unknown resource kind/, result["message"])
  end

  # ExecuteAnalysisTool tests

  def test_execute_analysis_tool_list_mode
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool)

    assert_equal 3, result["total"]
    names = result["analyses"].map { |a| a["name"] }

    assert_includes names, "Analysis:Test:Simple"
    assert_includes names, "Analysis:Test:NoScript"
    assert_includes names, "Analysis:Test:Failing"
  end

  def test_execute_analysis_tool_list_includes_metadata
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool)

    simple = result["analyses"].find { |a| a["name"] == "Analysis:Test:Simple" }

    assert_equal "A simple test analysis", simple["description"]
    assert_equal "ruby", simple["handler"]
    assert_equal "10s", simple["timeout"]
  end

  def test_execute_analysis_tool_runs_script
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool, name: "Analysis:Test:Simple")

    assert_equal "Analysis:Test:Simple", result["name"]
    assert result["success"]
    assert_includes result["output"], "Test Results"
    assert_includes result["output"], "Analysis completed"
  end

  def test_execute_analysis_tool_not_found
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool, name: "Analysis:Nonexistent")

    assert result.key?("error")
    assert_match(/not found/, result["message"])
  end

  def test_execute_analysis_tool_no_script_error
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool, name: "Analysis:Test:NoScript")

    assert_equal "Analysis:Test:NoScript", result["name"]
    refute result["success"]
    assert_match(/No script/, result["error"])
  end

  def test_execute_analysis_tool_script_failure
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool, name: "Analysis:Test:Failing")

    assert_equal "Analysis:Test:Failing", result["name"]
    refute result["success"]
    assert_match(/Something went wrong/, result["error"])
  end

  def test_execute_analysis_tool_includes_duration
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool, name: "Analysis:Test:Simple")

    assert result.key?("duration")
    assert_kind_of Float, result["duration"]
  end

  def test_execute_analysis_tool_verbose_mode
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool, name: "Analysis:Test:Simple", verbose: true)

    assert result["success"]
    assert_includes result["output"], "Test Results"
  end

  def test_execute_analysis_tool_success_metadata
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool, name: "Analysis:Test:Simple")

    assert result.key?("has_findings")
    assert result.key?("warning_count")
    assert result.key?("error_count")
    assert_equal 0, result["warning_count"]
    assert_equal 0, result["error_count"]
  end

  # Mock Database class
  class MockDatabase
    attr_accessor :instances

    def initialize
      @instances = {}
    end

    def add_instance(kind, name, annotations = {})
      klass = Archsight::Resources[kind]
      raw = {
        "apiVersion" => "architecture/v1alpha1",
        "kind" => kind,
        "metadata" => {
          "name" => name,
          "annotations" => annotations
        },
        "spec" => {}
      }
      path_ref = Archsight::LineReference.new("test", 0)
      instance = klass.new(raw, path_ref)

      @instances[klass] ||= {}
      @instances[klass][name] = instance
      instance
    end

    def link(from_kind, from_name, verb, relation_kind, to_kind, to_name)
      from_klass = Archsight::Resources[from_kind]
      to_klass = Archsight::Resources[to_kind]

      from_instance = @instances[from_klass][from_name]
      to_instance = @instances[to_klass][to_name]

      from_instance.raw["spec"][verb.to_s] ||= {}
      from_instance.raw["spec"][verb.to_s][relation_kind.to_s] ||= []
      from_instance.raw["spec"][verb.to_s][relation_kind.to_s] << to_instance

      to_instance.referenced_by(from_instance)
    end

    def instances_by_kind(kind)
      klass = Archsight::Resources[kind]
      @instances[klass] || {}
    end

    def instance_by_kind(kind, name)
      instances_by_kind(kind)[name]
    end

    def search(query)
      results = []
      re = Regexp.new(query, "i")
      @instances.each_value do |h|
        h.each_value do |i|
          results << i if i.name =~ re
        end
      end
      results
    end

    def query(query_string)
      q = Archsight::Query.parse(query_string)
      q.filter(self)
    end
  end
end
