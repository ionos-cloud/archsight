# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/resources"

class EvaluatorTest < Minitest::Test
  def setup
    @db = MockDatabase.new

    # Create TechnologyArtifacts
    @db.add_instance("TechnologyArtifact", "repo-active", {
                       "activity/status" => "active",
                       "repository/artifacts" => "container",
                       "scc/language/Go/loc" => "15000"
                     })
    @db.add_instance("TechnologyArtifact", "repo-abandoned", {
                       "activity/status" => "abandoned",
                       "repository/artifacts" => "binary"
                     })
    @db.add_instance("TechnologyArtifact", "repo-chart", {
                       "activity/status" => "active",
                       "repository/artifacts" => "chart"
                     })
    @db.add_instance("TechnologyArtifact", "repo-tagged", {
                       "activity/status" => "active",
                       "architecture/tags" => "customer-support, internal, api"
                     })

    # Create ApplicationInterface
    @db.add_instance("ApplicationInterface", "Kubernetes:RestAPI", {
                       "activity/status" => "active"
                     })

    # Create ApplicationComponent
    @db.add_instance("ApplicationComponent", "MyService", {
                       "activity/status" => "active",
                       "repository/artifacts" => "container"
                     })

    # Set up relations:
    # MyService (ApplicationComponent) exposes Kubernetes:RestAPI (ApplicationInterface)
    @db.link("ApplicationComponent", "MyService", :exposes, :applicationInterfaces, "ApplicationInterface",
             "Kubernetes:RestAPI")

    # MyService (ApplicationComponent) realizedThrough repo-active (TechnologyArtifact)
    @db.link("ApplicationComponent", "MyService", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "repo-active")
  end

  # Simple annotation tests
  def test_equals_match
    query = Archsight::Query.parse('activity/status == "active"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "repo-chart"
    refute_includes names, "repo-abandoned"
  end

  def test_not_equals
    query = Archsight::Query.parse('activity/status != "abandoned"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    refute_includes names, "repo-abandoned"
  end

  def test_numeric_greater_than
    query = Archsight::Query.parse("scc/language/Go/loc > 10000")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_equal 1, results.length
  end

  def test_numeric_less_than
    query = Archsight::Query.parse("scc/language/Go/loc < 20000")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
  end

  # Numeric equality tests
  def test_numeric_equality
    query = Archsight::Query.parse("scc/language/Go/loc == 15000")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_equal 1, results.length
  end

  def test_numeric_equality_no_match
    query = Archsight::Query.parse("scc/language/Go/loc == 99999")
    results = query.filter(@db)

    assert_empty results
  end

  def test_numeric_inequality
    query = Archsight::Query.parse("scc/language/Go/loc != 15000")
    results = query.filter(@db)
    names = results.map(&:name)

    refute_includes names, "repo-active"
  end

  def test_numeric_equality_with_float
    @db.add_instance("TechnologyArtifact", "repo-float", {
                       "score" => "3.14"
                     })

    query = Archsight::Query.parse("score == 3.14")
    results = query.filter(@db)

    assert_equal 1, results.length
    assert_equal "repo-float", results.first.name
  end

  def test_regex_match
    query = Archsight::Query.parse('repository/artifacts =~ "cont.*"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    refute_includes names, "repo-chart"
  end

  # Annotation existence tests
  def test_annotation_exists_match
    query = Archsight::Query.parse("activity/status?")
    results = query.filter(@db)
    names = results.map(&:name)

    # All instances with activity/status annotation
    assert_includes names, "repo-active"
    assert_includes names, "repo-abandoned"
    assert_includes names, "repo-chart"
    assert_includes names, "repo-tagged"
  end

  def test_annotation_not_exists
    query = Archsight::Query.parse("! scc/language/Go/loc?")
    results = query.filter(@db)
    names = results.map(&:name)

    # Instances without Go LOC
    refute_includes names, "repo-active" # has it
    assert_includes names, "repo-abandoned" # doesn't have it
    assert_includes names, "repo-chart" # doesn't have it
  end

  def test_annotation_exists_combined
    query = Archsight::Query.parse("activity/status? & ! scc/language/Go/loc?")
    results = query.filter(@db)
    names = results.map(&:name)

    # Has activity/status but not scc/language/Go/loc
    assert_includes names, "repo-abandoned"
    assert_includes names, "repo-chart"
    refute_includes names, "repo-active"
  end

  def test_annotation_exists_with_kind_filter
    query = Archsight::Query.parse("TechnologyArtifact: scc/language/Go/loc?")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_equal 1, results.length
    assert_includes names, "repo-active"
  end

  def test_annotation_exists_deep_path
    query = Archsight::Query.parse("scc/language/Go/loc?")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_equal 1, results.length
    assert_includes names, "repo-active"
  end

  # List annotation tests (filter: :list)
  def test_list_annotation_equals_match
    query = Archsight::Query.parse('architecture/tags == "customer-support"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-tagged"
    assert_equal(1, names.count { |n| n == "repo-tagged" })
  end

  def test_list_annotation_equals_match_middle_value
    query = Archsight::Query.parse('architecture/tags == "internal"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-tagged"
  end

  def test_list_annotation_equals_no_match
    query = Archsight::Query.parse('architecture/tags == "nonexistent"')
    results = query.filter(@db)
    names = results.map(&:name)

    refute_includes names, "repo-tagged"
  end

  def test_list_annotation_not_equals
    query = Archsight::Query.parse('architecture/tags != "customer-support"')
    results = query.filter(@db)
    names = results.map(&:name)

    refute_includes names, "repo-tagged"
  end

  def test_list_annotation_regex_match
    query = Archsight::Query.parse('architecture/tags =~ "customer.*"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-tagged"
  end

  def test_list_annotation_regex_match_any_value
    query = Archsight::Query.parse('architecture/tags =~ "^api$"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-tagged"
  end

  # IN operator tests
  def test_in_single_value_match
    query = Archsight::Query.parse('repository/artifacts in ("container")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "MyService"
    refute_includes names, "repo-chart"
  end

  def test_in_multiple_values_match
    query = Archsight::Query.parse('repository/artifacts in ("container", "chart")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "repo-chart"
    refute_includes names, "repo-abandoned"
  end

  def test_in_no_match
    query = Archsight::Query.parse('repository/artifacts in ("nonexistent", "other")')
    results = query.filter(@db)
    names = results.map(&:name)

    refute_includes names, "repo-active"
    refute_includes names, "repo-chart"
  end

  def test_in_combined_with_and
    query = Archsight::Query.parse('activity/status == "active" & repository/artifacts in ("container", "chart")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "repo-chart"
    refute_includes names, "repo-abandoned"
  end

  def test_in_equivalent_to_or
    # in ("container", "chart") should be equivalent to == "container" | == "chart"
    query_in = Archsight::Query.parse('repository/artifacts in ("container", "chart")')
    query_or = Archsight::Query.parse('repository/artifacts == "container" | repository/artifacts == "chart"')

    results_in = query_in.filter(@db).map(&:name).sort
    results_or = query_or.filter(@db).map(&:name).sort

    assert_equal results_or, results_in
  end

  def test_in_with_list_annotation
    query = Archsight::Query.parse('architecture/tags in ("customer-support", "external")')
    results = query.filter(@db)
    names = results.map(&:name)

    # repo-tagged has 'customer-support, internal, api'
    assert_includes names, "repo-tagged"
  end

  def test_in_with_list_annotation_multiple_matches
    query = Archsight::Query.parse('architecture/tags in ("internal", "api")')
    results = query.filter(@db)
    names = results.map(&:name)

    # repo-tagged has 'customer-support, internal, api' - both match
    assert_includes names, "repo-tagged"
  end

  def test_in_with_list_annotation_no_match
    query = Archsight::Query.parse('architecture/tags in ("external", "public")')
    results = query.filter(@db)
    names = results.map(&:name)

    refute_includes names, "repo-tagged"
  end

  def test_in_with_kind_filter
    query = Archsight::Query.parse('TechnologyArtifact: repository/artifacts in ("container", "chart")')
    results = query.filter(@db)

    assert(results.all? { |r| r.kind == "TechnologyArtifact" })
    assert_equal 2, results.length # repo-active, repo-chart
  end

  # Kind filter tests
  def test_kind_filter
    query = Archsight::Query.parse('TechnologyArtifact: activity/status == "active"')
    results = query.filter(@db)

    assert(results.all? { |r| r.kind == "TechnologyArtifact" })
    assert_equal 3, results.length  # repo-active, repo-chart, repo-tagged
  end

  def test_kind_filter_alone
    query = Archsight::Query.parse("TechnologyArtifact:")
    results = query.filter(@db)

    assert(results.all? { |r| r.kind == "TechnologyArtifact" })
    assert_equal 4, results.length  # All TechnologyArtifacts
  end

  def test_kind_condition
    query = Archsight::Query.parse('kind == "ApplicationInterface"')
    results = query.filter(@db)

    assert_equal 1, results.length
    assert_equal "Kubernetes:RestAPI", results.first.name
  end

  # Name condition tests
  def test_name_equals
    query = Archsight::Query.parse('name == "MyService"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_equal 1, results.length
    assert_includes names, "MyService"
  end

  def test_name_not_equals
    query = Archsight::Query.parse('name != "MyService"')
    results = query.filter(@db)
    names = results.map(&:name)

    refute_includes names, "MyService"
    assert_includes names, "repo-active"
  end

  def test_name_regex
    query = Archsight::Query.parse('name =~ "repo-.*"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_equal 4, results.length
    assert_includes names, "repo-active"
    assert_includes names, "repo-abandoned"
    assert_includes names, "repo-chart"
    assert_includes names, "repo-tagged"
  end

  def test_name_shortcut
    # Bare identifier should match name with regex
    query = Archsight::Query.parse("repo")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_equal 4, results.length
    assert_includes names, "repo-active"
    assert_includes names, "repo-abandoned"
    assert_includes names, "repo-chart"
    assert_includes names, "repo-tagged"
  end

  def test_name_shortcut_case_insensitive
    query = Archsight::Query.parse("REPO")
    results = query.filter(@db)

    assert_equal 4, results.length
  end

  def test_name_shortcut_combined_with_annotation
    query = Archsight::Query.parse('repo & activity/status == "active"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_equal 3, results.length
    assert_includes names, "repo-active"
    assert_includes names, "repo-chart"
    assert_includes names, "repo-tagged"
    refute_includes names, "repo-abandoned"
  end

  def test_name_shortcut_with_kind_filter
    query = Archsight::Query.parse("TechnologyArtifact: active")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_equal 1, results.length
    assert_includes names, "repo-active"
  end

  # Logical operator tests
  def test_and_both_match
    query = Archsight::Query.parse('activity/status == "active" & repository/artifacts == "container"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "MyService"
    refute_includes names, "repo-chart"
  end

  def test_or_either_match
    query = Archsight::Query.parse('repository/artifacts == "container" | repository/artifacts == "chart"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "repo-chart"
    refute_includes names, "repo-abandoned"
  end

  def test_not_operator
    query = Archsight::Query.parse('! activity/status == "abandoned"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    refute_includes names, "repo-abandoned"
  end

  def test_complex_and_or
    # (container | chart) & active
    query = Archsight::Query.parse('(repository/artifacts == "container" | repository/artifacts == "chart") & activity/status == "active"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "repo-chart"
  end

  # Outgoing relation tests
  def test_outgoing_direct_to_kind
    # MyService exposes ApplicationInterface
    query = Archsight::Query.parse("-> ApplicationInterface")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService"
    refute_includes names, "repo-active"
  end

  def test_outgoing_direct_to_instance
    query = Archsight::Query.parse('-> "Kubernetes:RestAPI"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService"
  end

  def test_outgoing_transitive
    # MyService -> TechnologyArtifact (repo-active)
    query = Archsight::Query.parse('~> "repo-active"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService"
  end

  def test_outgoing_transitive_to_kind
    # MyService -> TechnologyArtifact
    query = Archsight::Query.parse("~> TechnologyArtifact")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService"
  end

  # Incoming relation tests
  def test_incoming_direct_from_kind
    # Kubernetes:RestAPI <- ApplicationComponent (MyService)
    query = Archsight::Query.parse("<- ApplicationComponent")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "Kubernetes:RestAPI"
  end

  def test_incoming_direct_from_instance
    query = Archsight::Query.parse('<- "MyService"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "Kubernetes:RestAPI"
    assert_includes names, "repo-active"
  end

  def test_incoming_transitive
    # repo-active <- MyService
    query = Archsight::Query.parse('<~ "MyService"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "Kubernetes:RestAPI"
  end

  def test_incoming_transitive_from_kind
    query = Archsight::Query.parse("<~ ApplicationComponent")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "Kubernetes:RestAPI"
  end

  # Combined tests
  def test_annotation_and_relation
    query = Archsight::Query.parse('activity/status == "active" & -> ApplicationInterface')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService"
    refute_includes names, "repo-active"
  end

  def test_kind_filter_with_relation
    query = Archsight::Query.parse("ApplicationComponent: -> ApplicationInterface")
    results = query.filter(@db)

    assert_equal 1, results.length
    assert_equal "MyService", results.first.name
  end

  # Instance-level matches test
  def test_matches_single_instance
    instance = @db.instances_by_kind("TechnologyArtifact")["repo-active"]
    query = Archsight::Query.parse('activity/status == "active"')

    assert query.matches?(instance, database: @db)
  end

  def test_not_matches_single_instance
    instance = @db.instances_by_kind("TechnologyArtifact")["repo-abandoned"]
    query = Archsight::Query.parse('activity/status == "active"')

    refute query.matches?(instance, database: @db)
  end

  # Database integration test
  def test_database_query_method
    results = @db.query('TechnologyArtifact: activity/status == "active"')
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "repo-chart"
  end

  def test_database_instance_matches_method
    instance = @db.instances_by_kind("TechnologyArtifact")["repo-active"]

    assert @db.instance_matches?(instance, 'activity/status == "active"')
    refute @db.instance_matches?(instance, 'activity/status == "abandoned"')
  end

  # Subquery tests
  def test_subquery_outgoing_direct_name_match
    # MyService -> $(RestAPI) should match because MyService exposes Kubernetes:RestAPI
    query = Archsight::Query.parse("-> $(RestAPI)")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService"
    refute_includes names, "repo-active"
  end

  def test_subquery_outgoing_direct_kind_filter
    # Find resources that relate to any TechnologyArtifact
    query = Archsight::Query.parse("-> $(TechnologyArtifact:)")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService" # MyService -> repo-active
  end

  def test_subquery_outgoing_direct_with_annotation
    # Find resources that relate to active TechnologyArtifacts
    query = Archsight::Query.parse('-> $(TechnologyArtifact: activity/status == "active")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService"
  end

  def test_subquery_outgoing_transitive
    # Find resources that transitively reach repo-active via subquery
    query = Archsight::Query.parse("~> $(repo-active)")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService"
  end

  def test_subquery_incoming_direct
    # Find resources that are referenced by MyService
    query = Archsight::Query.parse('<- $(name == "MyService")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "Kubernetes:RestAPI"
    assert_includes names, "repo-active"
  end

  def test_subquery_incoming_from_kind
    # Find resources referenced by ApplicationComponents
    query = Archsight::Query.parse("<- $(ApplicationComponent:)")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "Kubernetes:RestAPI"
    assert_includes names, "repo-active"
  end

  def test_subquery_incoming_transitive
    # Find resources transitively reached by MyService
    query = Archsight::Query.parse("<~ $(MyService)")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "Kubernetes:RestAPI"
    assert_includes names, "repo-active"
  end

  def test_subquery_empty_result
    # Subquery returns no results - relation should not match
    query = Archsight::Query.parse("-> $(nonexistent)")
    results = query.filter(@db)

    assert_empty results
  end

  def test_subquery_combined_with_annotation
    # Find active resources that relate to TechnologyArtifacts
    query = Archsight::Query.parse('activity/status == "active" & -> $(TechnologyArtifact:)')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService"
    refute_includes names, "repo-abandoned"
  end

  def test_nested_subquery
    # Find resources that relate to something that relates to repo-active
    # First subquery finds things pointing to repo-active (MyService)
    # Then main query finds things pointing to those (nothing directly)
    query = Archsight::Query.parse("-> $(-> $(repo-active))")
    results = query.filter(@db)

    # MyService -> repo-active, so $(-> $(repo-active)) = [MyService]
    # Nothing directly points to MyService in our test data except itself
    assert results.empty? || results.map(&:name).exclude?("repo-active")
  end

  # Performance optimization tests - ensure subquery caching works correctly
  def test_transitive_subquery_with_deep_graph
    # Create a deeper graph using valid relations:
    # BusinessProduct -> ApplicationService -> ApplicationComponent -> TechnologyArtifact
    @db.add_instance("BusinessProduct", "ProductA", { "activity/status" => "active" })
    @db.add_instance("ApplicationService", "ServiceA", { "activity/status" => "active" })
    @db.add_instance("ApplicationComponent", "ComponentA", { "activity/status" => "active" })
    @db.add_instance("TechnologyArtifact", "target-artifact",
                     { "activity/status" => "active", "repository/artifacts" => "container" })

    # ProductA -> ServiceA -> ComponentA -> target-artifact
    @db.link("BusinessProduct", "ProductA", :servedBy, :applicationServices, "ApplicationService", "ServiceA")
    @db.link("ApplicationService", "ServiceA", :realizedThrough, :applicationComponents, "ApplicationComponent",
             "ComponentA")
    @db.link("ApplicationComponent", "ComponentA", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "target-artifact")

    # Query: find resources that transitively reach TechnologyArtifacts with specific annotation
    # Test ApplicationService level
    query = Archsight::Query.parse('ApplicationService: ~> $(TechnologyArtifact: repository/artifacts == "container")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "ServiceA"

    # Test BusinessProduct level (deeper)
    query2 = Archsight::Query.parse('BusinessProduct: ~> $(TechnologyArtifact: repository/artifacts == "container")')
    results2 = query2.filter(@db)
    names2 = results2.map(&:name)

    assert_includes names2, "ProductA"

    # Test ApplicationComponent level (direct)
    query3 = Archsight::Query.parse('ApplicationComponent: ~> $(TechnologyArtifact: repository/artifacts == "container")')
    results3 = query3.filter(@db)
    names3 = results3.map(&:name)

    assert_includes names3, "ComponentA"
    assert_includes names3, "MyService" # from setup
  end

  def test_transitive_subquery_incoming_with_deep_graph
    # Create graph using valid relations:
    # BusinessProduct -> ApplicationService -> ApplicationComponent -> TechnologyArtifact
    @db.add_instance("BusinessProduct", "ProductB", { "activity/status" => "active" })
    @db.add_instance("ApplicationService", "ServiceB", { "activity/status" => "active" })
    @db.add_instance("ApplicationComponent", "ComponentB", { "activity/status" => "active" })
    @db.add_instance("TechnologyArtifact", "TargetRepo", { "activity/status" => "active" })

    # ProductB -> ServiceB -> ComponentB -> TargetRepo
    @db.link("BusinessProduct", "ProductB", :servedBy, :applicationServices, "ApplicationService", "ServiceB")
    @db.link("ApplicationService", "ServiceB", :realizedThrough, :applicationComponents, "ApplicationComponent",
             "ComponentB")
    @db.link("ApplicationComponent", "ComponentB", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "TargetRepo")

    # Query: find TechnologyArtifacts transitively reached by active ApplicationServices
    query = Archsight::Query.parse('TechnologyArtifact: <~ $(ApplicationService: activity/status == "active")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "TargetRepo"

    # Also test deeper: find TechnologyArtifacts transitively reached by BusinessProducts
    query2 = Archsight::Query.parse('TechnologyArtifact: <~ $(BusinessProduct: activity/status == "active")')
    results2 = query2.filter(@db)
    names2 = results2.map(&:name)

    assert_includes names2, "TargetRepo"
  end

  # Kind operator tests
  def test_kind_regex_match
    query = Archsight::Query.parse('kind =~ "Technology.*"')
    results = query.filter(@db)
    names = results.map(&:name)

    # Should match TechnologyArtifact
    assert_includes names, "repo-active"
    assert_includes names, "repo-abandoned"
    assert_includes names, "repo-chart"
    # Should not match ApplicationComponent, ApplicationInterface
    refute_includes names, "MyService"
    refute_includes names, "Kubernetes:RestAPI"
  end

  def test_kind_regex_match_application
    query = Archsight::Query.parse('kind =~ "Application.*"')
    results = query.filter(@db)
    names = results.map(&:name)

    # Should match ApplicationComponent and ApplicationInterface
    assert_includes names, "MyService"
    assert_includes names, "Kubernetes:RestAPI"
    # Should not match TechnologyArtifact
    refute_includes names, "repo-active"
  end

  def test_kind_in_single
    query = Archsight::Query.parse('kind in ("TechnologyArtifact")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "repo-abandoned"
    refute_includes names, "MyService"
  end

  def test_kind_in_multiple
    query = Archsight::Query.parse('kind in ("TechnologyArtifact", "ApplicationComponent")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "MyService"
    refute_includes names, "Kubernetes:RestAPI"
  end

  def test_kind_in_combined_with_annotation
    query = Archsight::Query.parse('kind in ("TechnologyArtifact", "ApplicationComponent") & activity/status == "active"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "MyService"
    refute_includes names, "repo-abandoned"
  end

  # Name IN operator tests
  def test_name_in_single
    query = Archsight::Query.parse('name in ("repo-active")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_equal 1, results.length
    assert_includes names, "repo-active"
  end

  def test_name_in_multiple
    query = Archsight::Query.parse('name in ("repo-active", "repo-chart", "MyService")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-active"
    assert_includes names, "repo-chart"
    assert_includes names, "MyService"
    refute_includes names, "repo-abandoned"
  end

  def test_name_in_combined_with_kind
    query = Archsight::Query.parse('TechnologyArtifact: name in ("repo-active", "repo-chart")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_equal 2, results.length
    assert_includes names, "repo-active"
    assert_includes names, "repo-chart"
  end

  def test_name_in_no_match
    query = Archsight::Query.parse('name in ("nonexistent-1", "nonexistent-2")')
    results = query.filter(@db)

    assert_equal 0, results.length
  end

  # Verb filter tests
  def setup_verb_filter_data
    # Create teams (BusinessActor)
    @db.add_instance("BusinessActor", "TeamA:Team", { "activity/status" => "active" })
    @db.add_instance("BusinessActor", "TeamB:Team", { "activity/status" => "active" })

    # Create artifact maintained by TeamA and contributed to by TeamB
    @db.add_instance("TechnologyArtifact", "repo-maintained", {
                       "activity/status" => "active",
                       "repository/artifacts" => "container"
                     })

    # repo-maintained is maintainedBy TeamA
    @db.link("TechnologyArtifact", "repo-maintained", :maintainedBy, :businessActors, "BusinessActor", "TeamA:Team")

    # repo-maintained is contributedBy TeamB
    @db.link("TechnologyArtifact", "repo-maintained", :contributedBy, :businessActors, "BusinessActor", "TeamB:Team")

    # Create a second artifact maintained by TeamB
    @db.add_instance("TechnologyArtifact", "repo-other", {
                       "activity/status" => "active",
                       "repository/artifacts" => "chart"
                     })
    @db.link("TechnologyArtifact", "repo-other", :maintainedBy, :businessActors, "BusinessActor", "TeamB:Team")

    # Create ApplicationComponent that realizes through repo-maintained
    @db.add_instance("ApplicationComponent", "ServiceA", { "activity/status" => "active" })
    @db.link("ApplicationComponent", "ServiceA", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "repo-maintained")
  end

  def test_outgoing_direct_with_include_verb
    setup_verb_filter_data

    # repo-maintained -{maintainedBy}> should match TeamA but not TeamB
    query = Archsight::Query.parse('TechnologyArtifact: -{maintainedBy}> "TeamA:Team"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-maintained"
  end

  def test_outgoing_direct_with_include_verb_no_match
    setup_verb_filter_data

    # repo-maintained -{maintainedBy}> TeamB:Team should NOT match
    # because TeamB is only contributedBy, not maintainedBy
    query = Archsight::Query.parse('TechnologyArtifact: -{maintainedBy}> "TeamB:Team"')
    results = query.filter(@db)
    names = results.map(&:name)

    # repo-maintained does NOT have maintainedBy TeamB, so it won't match
    refute_includes names, "repo-maintained"
    # repo-other is maintainedBy TeamB, so it should match
    assert_includes names, "repo-other"
  end

  def test_outgoing_direct_with_exclude_verb
    setup_verb_filter_data

    # repo-maintained -{!contributedBy}> TeamA should match (maintainedBy is not excluded)
    query = Archsight::Query.parse('TechnologyArtifact: -{!contributedBy}> "TeamA:Team"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-maintained"
  end

  def test_outgoing_direct_with_exclude_verb_no_match
    setup_verb_filter_data

    # repo-maintained -{!maintainedBy}> TeamA should NOT match
    # because the only relation to TeamA is maintainedBy, which is excluded
    query = Archsight::Query.parse('TechnologyArtifact: -{!maintainedBy}> "TeamA:Team"')
    results = query.filter(@db)
    names = results.map(&:name)

    refute_includes names, "repo-maintained"
  end

  def test_outgoing_direct_with_multiple_include_verbs
    setup_verb_filter_data

    # Find artifacts that have either maintainedBy OR contributedBy to TeamA
    query = Archsight::Query.parse('TechnologyArtifact: -{maintainedBy,contributedBy}> "TeamA:Team"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-maintained"
  end

  def test_outgoing_direct_with_multiple_exclude_verbs
    setup_verb_filter_data

    # Exclude both maintainedBy and contributedBy - no relations should match
    query = Archsight::Query.parse('TechnologyArtifact: -{!maintainedBy,contributedBy}> "TeamA:Team"')
    results = query.filter(@db)
    names = results.map(&:name)

    refute_includes names, "repo-maintained"
  end

  def test_outgoing_to_kind_with_include_verb
    setup_verb_filter_data

    # Find artifacts that have maintainedBy relation to any BusinessActor
    query = Archsight::Query.parse("TechnologyArtifact: -{maintainedBy}> BusinessActor")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-maintained"
    assert_includes names, "repo-other"
  end

  def test_outgoing_transitive_with_include_verb
    setup_verb_filter_data

    # ServiceA ~{realizedThrough}> TeamA:Team - follow realizedThrough then any relation
    # ServiceA -> repo-maintained -> TeamA (via maintainedBy)
    query = Archsight::Query.parse("ApplicationComponent: ~{realizedThrough}> TechnologyArtifact")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "ServiceA"
    assert_includes names, "MyService" # from setup - has realizedThrough to repo-active
  end

  def test_outgoing_transitive_with_exclude_verb
    setup_verb_filter_data

    # MyService has realizedThrough and exposes relations
    # ~{!exposes}> should exclude the exposes relation path
    query = Archsight::Query.parse("ApplicationComponent: ~{!exposes}> TechnologyArtifact")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "MyService" # still reaches via realizedThrough
    assert_includes names, "ServiceA"
  end

  def test_incoming_direct_with_include_verb
    setup_verb_filter_data

    # TeamA:Team receives maintainedBy from repo-maintained
    query = Archsight::Query.parse("BusinessActor: <{maintainedBy}- TechnologyArtifact")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "TeamA:Team"
    assert_includes names, "TeamB:Team" # also maintained by repo-other
  end

  def test_incoming_direct_with_exclude_verb
    setup_verb_filter_data

    # TeamB receives contributedBy from repo-maintained, but also maintainedBy from repo-other
    # <{!maintainedBy}- should only match contributedBy relations
    query = Archsight::Query.parse('BusinessActor: <{!maintainedBy}- "repo-maintained"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "TeamB:Team"  # has contributedBy from repo-maintained
    refute_includes names, "TeamA:Team"  # only has maintainedBy from repo-maintained
  end

  def test_incoming_transitive_with_include_verb
    setup_verb_filter_data

    # repo-maintained <{realizedThrough}~ ApplicationComponent
    # Find TechnologyArtifacts that are reached via realizedThrough from ApplicationComponents
    query = Archsight::Query.parse("TechnologyArtifact: <{realizedThrough}~ ApplicationComponent")
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-maintained"
    assert_includes names, "repo-active" # from setup - MyService realizes through it
  end

  def test_verb_filter_with_subquery
    setup_verb_filter_data

    # Find artifacts that have maintainedBy to active teams
    query = Archsight::Query.parse('TechnologyArtifact: -{maintainedBy}> $(BusinessActor: activity/status == "active")')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-maintained"
    assert_includes names, "repo-other"
  end

  def test_verb_filter_with_none_target
    setup_verb_filter_data

    # Find TechnologyArtifacts with no maintainedBy relations
    # repo-active and repo-abandoned have no maintainedBy
    query = Archsight::Query.parse("TechnologyArtifact: -{maintainedBy}> none")
    results = query.filter(@db)
    names = results.map(&:name)

    # repo-maintained and repo-other have maintainedBy
    refute_includes names, "repo-maintained"
    refute_includes names, "repo-other"
    # repo-active, repo-abandoned, repo-chart, repo-tagged don't have maintainedBy
    assert_includes names, "repo-active"
    assert_includes names, "repo-abandoned"
    assert_includes names, "repo-chart"
    assert_includes names, "repo-tagged"
  end

  def test_standard_relation_matches_all_verbs
    setup_verb_filter_data

    # Standard -> without verb filter should match all verbs
    # repo-maintained -> TeamA (maintainedBy) and -> TeamB (contributedBy)
    query = Archsight::Query.parse('TechnologyArtifact: -> "TeamA:Team"')
    results = query.filter(@db)
    names = results.map(&:name)

    assert_includes names, "repo-maintained"

    # Also check TeamB
    query2 = Archsight::Query.parse('TechnologyArtifact: -> "TeamB:Team"')
    results2 = query2.filter(@db)
    names2 = results2.map(&:name)

    assert_includes names2, "repo-maintained"
  end

  # Mock Database class for testing
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

      # Set up the relation in spec
      from_instance.raw["spec"][verb.to_s] ||= {}
      from_instance.raw["spec"][verb.to_s][relation_kind.to_s] ||= []
      from_instance.raw["spec"][verb.to_s][relation_kind.to_s] << to_instance

      # Mark the target as referenced
      to_instance.referenced_by(from_instance)
    end

    def instances_by_kind(kind)
      klass = Archsight::Resources[kind]
      @instances[klass] || {}
    end

    def query(query_string)
      q = Archsight::Query.parse(query_string)
      q.filter(self)
    end

    def instance_matches?(instance, query_string)
      q = Archsight::Query.parse(query_string)
      q.matches?(instance, database: self)
    end
  end
end
