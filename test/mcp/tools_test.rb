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

  def test_query_tool_brief_has_kind_source_and_generated_with_kind_prefix
    result = call_tool(Archsight::MCP::QueryTool, query: "TechnologyArtifact: repo-active", output: "brief")
    hit = result["resources"].first

    assert_equal "TechnologyArtifact", hit["kind"]
    assert_equal "test:0", hit["source"]
    refute hit["generated"]
    refute hit.key?("sources")
  end

  def test_query_tool_marks_generated_and_merged_sources
    inst = @db.add_instance("TechnologyArtifact", "gen", { "generated/script" => "import-x" })
    other = Archsight::Resources["TechnologyArtifact"].new(inst.raw.dup, Archsight::LineReference.new("hand.yaml", 7))
    inst.merge!(other)
    result = call_tool(Archsight::MCP::QueryTool, query: "name == \"gen\"", output: "complete")
    hit = result["resources"].first

    assert hit["generated"]
    assert_equal ["test:0", "hand.yaml:7"], hit["sources"]
  end

  def test_analyze_resource_shows_source_of_target_and_relations
    result = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "ApplicationComponent", name: "MyService")

    assert_equal "test:0", result["source"]
    assert_includes result["related"].map { |r| r["name"] }, "repo-active"
    assert(result["related"].all? { |r| r.key?("source") && r.key?("generated") })
  end

  def test_query_tool_fields_projects_annotations_and_relations
    result = call_tool(Archsight::MCP::QueryTool, query: "ApplicationComponent: MyService",
                                                  fields: ["activity/status", "exposes"])
    hit = result["resources"].first

    assert_equal({ "activity/status" => "active" }, hit["metadata"]["annotations"])
    assert_equal ["exposes"], hit["spec"].keys
  end

  def test_query_tool_cuts_oversized_result_and_says_how_to_narrow
    stub_const_budget(300) do
      result = call_tool(Archsight::MCP::QueryTool, query: "repo")

      assert_operator result["resources"].length, :<, 2
      assert_match(/size budget/, result["truncated"])
    end
  end

  def test_query_tool_relation_query_shows_why_it_matched
    result = call_tool(Archsight::MCP::QueryTool, query: "-> TechnologyArtifact", output: "brief")
    hit = result["resources"].first

    assert_equal "MyService", hit["name"]
    assert_equal [{ "verb" => "realizedThrough", "direction" => "out", "kind" => "TechnologyArtifact", "name" => "repo-active" }],
                 hit["matched_via"]

    incoming = call_tool(Archsight::MCP::QueryTool, query: '<- "MyService"', output: "brief")

    assert_includes incoming["resources"].map { |r| r["matched_via"].first["verb"] }, "realizedThrough"
    refute call_tool(Archsight::MCP::QueryTool, query: "repo", output: "brief")["resources"].first.key?("matched_via")
  end

  def test_query_tool_warns_about_unknown_annotation_keys
    result = call_tool(Archsight::MCP::QueryTool, query: 'TechnologyArtifact: activity/statuss == "active"')

    assert_equal 0, result["total"]
    assert_match(%r{unknown annotation key "activity/statuss"; known keys for TechnologyArtifact: activity/status},
                 result["warnings"].first)

    without_kind = call_tool(Archsight::MCP::QueryTool, query: 'nonsense/key == "x"', output: "count")

    assert_match(/closest known keys over all kinds/, without_kind["warnings"].first)

    known = call_tool(Archsight::MCP::QueryTool, query: 'TechnologyArtifact: activity/status == "nope"')

    assert_equal 0, known["total"]
    refute known.key?("warnings")
    refute call_tool(Archsight::MCP::QueryTool, query: "repo").key?("warnings")
  end

  def test_query_tool_text_search_shows_key_and_snippet
    @db.add_instance("ApplicationService", "Billing", {
                       "architecture/description" => "#{"Handles invoices for all customers in the shop. " * 3}Failover goes to the standby region.",
                       "link/jira" => "https://tracker.example/PROJ-1234"
                     })
    result = call_tool(Archsight::MCP::QueryTool, query: 'text =~ "failover"', output: "brief")
    hit = result["resources"].first

    assert_equal "Billing", hit["name"]
    assert_equal "architecture/description", hit["matched_text"].first["key"]
    assert_match(/\A….*Failover goes to the standby region\.\z/, hit["matched_text"].first["snippet"])

    ticket = call_tool(Archsight::MCP::QueryTool, query: 'text(link/*) =~ "PROJ-1234"', output: "brief")

    assert_equal "link/jira", ticket["resources"].first["matched_text"].first["key"]
    refute call_tool(Archsight::MCP::QueryTool, query: "Billing", output: "brief")["resources"].first.key?("matched_text")
    assert_match(%r{unknown annotation key "nope/key"},
                 call_tool(Archsight::MCP::QueryTool, query: 'text(nope/key) =~ "x"')["warnings"].first)
  end

  def test_summary_tool_explains_a_resource_through_its_layer_lens
    result = call_tool(Archsight::MCP::SummaryTool, name: "MyService")
    text = result["summary"]

    assert_equal %w[ApplicationComponent application], result.values_at("kind", "layer")
    assert_match(%r{\A# \[\[ApplicationComponent/MyService\]\]}, text)
    assert_match(%r{## Interfaces\n- exposes: \[\[ApplicationInterface/Kubernetes:RestAPI\]\]}, text)
    assert_match(%r{## Realized through\n- realizedThrough: \[\[TechnologyArtifact/repo-active\]\]}, text)
    refute_match(/## Used by|## Owners|## Evidence/, text)
    assert_match(/## Related in other layers\n- technology \(1\): TechnologyArtifact 1; `summary\(kind: "ApplicationComponent"/, text)
    assert_equal "test:0", result["source"]
  end

  def test_summary_tool_lens_override_and_config
    other = call_tool(Archsight::MCP::SummaryTool, name: "MyService", lens: "technology")["summary"]

    assert_match(/viewed through the technology lens/, other)
    refute_match(/## Interfaces/, other)

    @db.add_instance("Config", "default", { "config/type" => "summary", "summary/lens-application" => "out exposes: APIs" })
    configured = call_tool(Archsight::MCP::SummaryTool, name: "MyService")["summary"]

    assert_match(/## APIs/, configured)
    refute_match(/## Realized through/, configured)

    @db.instances_by_kind("Config")["default"].annotations["summary/lens-application"] = "broken line"

    assert_match(/## Interfaces/, call_tool(Archsight::MCP::SummaryTool, name: "MyService")["summary"])
    assert_match(/Unknown lens/, call_tool(Archsight::MCP::SummaryTool, name: "MyService", lens: "x")["message"])
  end

  def test_summary_tool_resolves_names_and_suggests
    @db.add_instance("TechnologyArtifact", "Shared", {})
    @db.add_instance("ApplicationComponent", "Shared", { "architecture/description" => "The component" })

    ambiguous = call_tool(Archsight::MCP::SummaryTool, name: "Shared")

    assert ambiguous["ambiguous"]
    assert_equal(["[[ApplicationComponent/Shared]]", "[[TechnologyArtifact/Shared]]"], ambiguous["candidates"].map { |c| c["link"] })
    assert_equal "The component", ambiguous["candidates"].first["description"]
    assert_equal "TechnologyArtifact", call_tool(Archsight::MCP::SummaryTool, name: "Shared", kind: "TechnologyArtifact")["kind"]
    assert_equal "MyService", call_tool(Archsight::MCP::SummaryTool, name: "myservice")["name"]
    assert_match(%r{Did you mean: ApplicationComponent/MyService}, call_tool(Archsight::MCP::SummaryTool, name: "MyServise")["message"])
  end

  def test_summary_is_bounded_with_follow_up_calls
    20.times do |i|
      name = format("svc-%02d", i)
      @db.add_instance("ApplicationInterface", name, {})
      @db.link("ApplicationComponent", "MyService", :exposes, :applicationInterfaces, "ApplicationInterface", name)
    end

    text = call_tool(Archsight::MCP::SummaryTool, name: "MyService", per_section: 3)["summary"]

    assert_match(/exposes: .*\(21 in total, 18 more: `relations\(kind: "ApplicationComponent", name: "MyService", verb: "exposes", direction: "out"\)`\)/, text)

    small = Archsight::Summary::Builder.new(@db, max_chars: 400).call(@db.instance_by_kind("ApplicationComponent", "MyService"))

    assert_operator small.length, :<=, 700
    assert_match(/left out/, small)
  end

  def test_summary_deep_sections_follow_verbs_stepwise
    @db.add_instance("ApplicationComponent", "Upstream", {})
    @db.add_instance("ApplicationComponent", "Far", {})
    @db.link("ApplicationComponent", "MyService", :dependsOn, :applicationComponents, "ApplicationComponent", "Upstream")
    @db.link("ApplicationComponent", "Upstream", :dependsOn, :applicationComponents, "ApplicationComponent", "Far")
    @db.add_instance("Config", "default", { "config/type" => "summary", "summary/lens-application" => "out dependsOn depth=2: Needs" })

    text = call_tool(Archsight::MCP::SummaryTool, name: "MyService")["summary"]

    assert_match(%r{## Needs\n- dependsOn \(step 1\): \[\[ApplicationComponent/Upstream\]\]\n- dependsOn \(step 2\): \[\[ApplicationComponent/Far\]\]}, text)
  end

  def test_summary_tool_description_has_an_example_per_layer
    desc = Archsight::MCP::SummaryTool.description

    %w[MotivationRequirement ApplicationComponent TechnologyNode BusinessProcess].each { |kind| assert_includes desc, kind }
    assert_match(%r{\[\[Kind/Name\]\]}, desc)
  end

  def test_tool_descriptions_carry_pitfalls_and_flows
    [Archsight::MCP::QueryTool, Archsight::MCP::AnalyzeResourceTool, Archsight::MCP::RelationsTool,
     Archsight::MCP::ResourceDocTool, Archsight::MCP::ExecuteAnalysisTool].each do |tool|
      assert_match(/PITFALLS/, tool.description, tool.tool_name)
      assert_match(/TYPICAL FLOW/, tool.description, tool.tool_name)
    end
    assert_match(/orphans/, Archsight::MCP::QueryTool.description)
    assert_match(/exclude_kinds/, Archsight::MCP::AnalyzeResourceTool.description)
    assert_match(/no parameters/, Archsight::MCP::ExecuteAnalysisTool.description)
  end

  def test_execute_analysis_unknown_name_suggests_analyses
    result = call_tool(Archsight::MCP::ExecuteAnalysisTool, name: "Analysis:Test:Simpel")

    assert_match(%r{Did you mean: Analysis/Analysis:Test:Simple}, result["message"])
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

  def test_query_tool_invalid_regex_is_a_query_error
    result = call_tool(Archsight::MCP::QueryTool, query: 'name =~ "["')

    assert_equal "Query error", result["error"]
    assert_includes result["message"], "Invalid regular expression"
    assert_equal 'name =~ "["', result["query"]
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
  def test_impact_exclude_kinds_verbs_direction_and_limit
    base = { kind: "ApplicationInterface", name: "Kubernetes:RestAPI", impact: true }
    all = call_tool(Archsight::MCP::AnalyzeResourceTool, **base)

    assert_equal 1, all["summary"]["total_impacted"]

    excluded = call_tool(Archsight::MCP::AnalyzeResourceTool, **base, exclude_kinds: ["ApplicationComponent"])

    assert_equal 0, excluded["summary"]["total_impacted"]

    only = call_tool(Archsight::MCP::AnalyzeResourceTool, **base, kinds: ["ApplicationComponent"], verbs: ["exposes"])

    assert_equal 1, only["summary"]["total_impacted"]
    assert_equal({ "kinds" => ["ApplicationComponent"], "verbs" => ["exposes"] }, only["filters"])

    out = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "ApplicationComponent", name: "MyService",
                                                         impact: true, direction: "out")

    assert_equal %w[ApplicationInterface TechnologyArtifact], out["summary"]["by_kind"].keys.sort

    limited = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "ApplicationComponent", name: "MyService",
                                                             impact: true, direction: "out", limit: 1)

    assert_equal 2, limited["summary"]["total_impacted"]
    assert_equal 1, limited["impacted_resources"].values.flatten.length
    assert_match(/1 more entries not listed/, limited["truncated"])
  end

  def test_relations_tool_filters_direct_relations
    tool = Archsight::MCP::RelationsTool
    all = call_tool(tool, kind: "ApplicationComponent", name: "MyService")

    assert_equal 2, all["total"]
    assert_equal %w[exposes realizedThrough], all["relations"].keys.sort

    one = call_tool(tool, kind: "ApplicationComponent", name: "MyService", verb: "realizedThrough")

    assert_equal [{ "verb" => "realizedThrough", "direction" => "out", "kind" => "TechnologyArtifact", "name" => "repo-active" }],
                 one["relations"]["realizedThrough"]

    incoming = call_tool(tool, kind: "TechnologyArtifact", name: "repo-active", direction: "in", target_kind: "ApplicationComponent")

    assert_equal "MyService", incoming["relations"]["realizedThrough"].first["name"]
    assert_equal "in", incoming["relations"]["realizedThrough"].first["direction"]

    none = call_tool(tool, kind: "ApplicationComponent", name: "MyService", verb: "servedBy")

    assert_equal 0, none["total"]
    assert_match(/Verbs present: exposes, realizedThrough/, none["warning"])
  end

  def test_unknown_names_get_suggestions_across_kinds
    miss = call_tool(Archsight::MCP::RelationsTool, kind: "ApplicationComponent", name: "myservice")

    assert_equal({ "kind" => "ApplicationComponent", "name" => "MyService" }, miss["suggestions"].first)

    typo = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "ApplicationInterface", name: "Kubernetes:RestAPl")

    assert_match(%r{Did you mean: ApplicationInterface/Kubernetes:RestAPI}, typo["message"])

    wrong_kind = call_tool(Archsight::MCP::AnalyzeResourceTool, kind: "TechnologyArtifact", name: "MyService")

    assert_equal "ApplicationComponent", wrong_kind["suggestions"].first["kind"]
    assert_operator Archsight::MCP.suggest("repo", limit: 5).length, :<=, 5
    assert_empty Archsight::MCP.suggest("zzzzzzzzzz")
  end

  def test_resource_doc_list_is_compact_and_sections_work
    list = Archsight::MCP::ResourceDocTool.new.call

    assert_operator list.length, :<, 6_000

    description = call_tool(Archsight::MCP::ResourceDocTool, kind: "ApplicationComponent", section: "description")
    annotations = call_tool(Archsight::MCP::ResourceDocTool, kind: "ApplicationComponent", section: "annotations")

    refute_match(/^## Annotations/, description["documentation"])
    assert_match(/^## Annotations/, annotations["documentation"])
    refute_match(/^## Relations/, annotations["documentation"])
    assert_match(/Unknown section/, call_tool(Archsight::MCP::ResourceDocTool, kind: "ApplicationComponent", section: "x")["message"])
  end

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

  def stub_const_budget(chars)
    old = Archsight::MCP::MAX_RESPONSE_CHARS
    Archsight::MCP.send(:remove_const, :MAX_RESPONSE_CHARS)
    Archsight::MCP.const_set(:MAX_RESPONSE_CHARS, chars)
    yield
  ensure
    Archsight::MCP.send(:remove_const, :MAX_RESPONSE_CHARS)
    Archsight::MCP.const_set(:MAX_RESPONSE_CHARS, old)
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

      to_instance.referenced_by(from_instance, verb)
    end

    def instances_by_kind(kind)
      klass = Archsight::Resources[kind]
      @instances[klass] || {}
    end

    def instance_by_kind(kind, name)
      instances_by_kind(kind)[name]
    end

    def instance_by_alias(_kind, _identifier)
      nil
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
