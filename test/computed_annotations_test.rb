# frozen_string_literal: true

require_relative "test_helper"
require "archsight/annotations/computed"

class ComputedAnnotationsTest < Minitest::Test
  def setup
    @db = MockDatabase.new

    # Create TechnologyArtifacts with various annotations
    @db.add_instance("TechnologyArtifact", "repo-go-large", {
                       "activity/status" => "active",
                       "scc/estimatedCost" => "50000",
                       "scc/languages" => "Go, Python"
                     })
    @db.add_instance("TechnologyArtifact", "repo-go-small", {
                       "activity/status" => "active",
                       "scc/estimatedCost" => "10000",
                       "scc/languages" => "Go"
                     })
    @db.add_instance("TechnologyArtifact", "repo-python", {
                       "activity/status" => "abandoned",
                       "scc/estimatedCost" => "25000",
                       "scc/languages" => "Python, JavaScript"
                     })
    @db.add_instance("TechnologyArtifact", "repo-no-lang", {
                       "activity/status" => "active"
                     })

    # Create ApplicationComponent
    @db.add_instance("ApplicationComponent", "MyComponent", {
                       "activity/status" => "active"
                     })

    # Create ApplicationService
    @db.add_instance("ApplicationService", "MyService", {
                       "activity/status" => "active"
                     })

    # Set up relations:
    # MyService -> MyComponent -> repo-go-large, repo-go-small, repo-python
    @db.link("ApplicationService", "MyService", :realizedThrough, :applicationComponents, "ApplicationComponent",
             "MyComponent")
    @db.link("ApplicationComponent", "MyComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "repo-go-large")
    @db.link("ApplicationComponent", "MyComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "repo-go-small")
    @db.link("ApplicationComponent", "MyComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "repo-python")
  end

  # === Aggregator Tests ===

  def test_aggregators_sum
    values = [10, 20, 30]

    assert_in_delta(60.0, Archsight::Annotations::ComputedAggregators.sum(values))
  end

  def test_aggregators_sum_with_strings
    values = %w[10 20 30]

    assert_in_delta(60.0, Archsight::Annotations::ComputedAggregators.sum(values))
  end

  def test_aggregators_sum_with_nil
    values = [10, nil, 30]

    assert_in_delta(40.0, Archsight::Annotations::ComputedAggregators.sum(values))
  end

  def test_aggregators_sum_empty
    assert_nil Archsight::Annotations::ComputedAggregators.sum([])
  end

  def test_aggregators_count
    values = ["a", "b", nil, "c"]

    assert_equal 3, Archsight::Annotations::ComputedAggregators.count(values)
  end

  def test_aggregators_count_empty
    assert_equal 0, Archsight::Annotations::ComputedAggregators.count([])
  end

  def test_aggregators_avg
    values = [10, 20, 30]

    assert_in_delta(20.0, Archsight::Annotations::ComputedAggregators.avg(values))
  end

  def test_aggregators_avg_empty
    assert_nil Archsight::Annotations::ComputedAggregators.avg([])
  end

  def test_aggregators_min
    values = [30, 10, 20]

    assert_in_delta(10.0, Archsight::Annotations::ComputedAggregators.min(values))
  end

  def test_aggregators_max
    values = [30, 10, 20]

    assert_in_delta(30.0, Archsight::Annotations::ComputedAggregators.max(values))
  end

  def test_aggregators_collect
    values = %w[Go Python Go JavaScript]

    assert_equal %w[Go JavaScript Python], Archsight::Annotations::ComputedAggregators.collect(values)
  end

  def test_aggregators_collect_with_comma_separated
    values = ["Go, Python", "JavaScript"]

    assert_equal %w[Go JavaScript Python], Archsight::Annotations::ComputedAggregators.collect(values)
  end

  def test_aggregators_first
    values = [nil, "first", "second"]

    assert_equal "first", Archsight::Annotations::ComputedAggregators.first(values)
  end

  def test_aggregators_first_empty
    assert_nil Archsight::Annotations::ComputedAggregators.first([])
  end

  def test_aggregators_most_common
    values = %w[Go Python Go Go Python]

    assert_equal "Go", Archsight::Annotations::ComputedAggregators.most_common(values)
  end

  def test_aggregators_most_common_with_comma_separated
    values = ["Go, Python", "Go", "Python, Go"]

    assert_equal "Go", Archsight::Annotations::ComputedAggregators.most_common(values)
  end

  def test_aggregators_most_common_empty
    assert_nil Archsight::Annotations::ComputedAggregators.most_common([])
  end

  # === RelationResolver Tests ===

  def test_relation_resolver_outgoing
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    results = resolver.outgoing(:TechnologyArtifact)
    names = results.map(&:name)

    assert_equal 3, results.length
    assert_includes names, "repo-go-large"
    assert_includes names, "repo-go-small"
    assert_includes names, "repo-python"
  end

  def test_relation_resolver_outgoing_no_filter
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    results = resolver.outgoing

    assert_operator results.length, :>=, 3 # All relations regardless of kind
  end

  def test_relation_resolver_outgoing_transitive
    instance = @db.instances_by_kind("ApplicationService")["MyService"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    results = resolver.outgoing_transitive(:TechnologyArtifact)
    names = results.map(&:name)

    # MyService -> MyComponent -> TechnologyArtifacts
    assert_equal 3, results.length
    assert_includes names, "repo-go-large"
    assert_includes names, "repo-go-small"
    assert_includes names, "repo-python"
  end

  def test_relation_resolver_incoming
    instance = @db.instances_by_kind("TechnologyArtifact")["repo-go-large"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    results = resolver.incoming(:ApplicationComponent)
    names = results.map(&:name)

    assert_equal 1, results.length
    assert_includes names, "MyComponent"
  end

  def test_relation_resolver_incoming_transitive
    instance = @db.instances_by_kind("TechnologyArtifact")["repo-go-large"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    results = resolver.incoming_transitive
    names = results.map(&:name)

    # repo-go-large <- MyComponent <- MyService
    assert_includes names, "MyComponent"
    assert_includes names, "MyService"
  end

  # === Query Selector Tests ===

  def test_relation_resolver_outgoing_with_query_selector
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    # Filter to only active artifacts
    results = resolver.outgoing('TechnologyArtifact: activity/status == "active"')
    names = results.map(&:name)

    assert_equal 2, results.length
    assert_includes names, "repo-go-large"
    assert_includes names, "repo-go-small"
    refute_includes names, "repo-python" # abandoned
  end

  def test_relation_resolver_outgoing_transitive_with_query_selector
    instance = @db.instances_by_kind("ApplicationService")["MyService"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    # Filter to only abandoned artifacts
    results = resolver.outgoing_transitive('TechnologyArtifact: activity/status == "abandoned"')
    names = results.map(&:name)

    assert_equal 1, results.length
    assert_includes names, "repo-python"
  end

  def test_relation_resolver_outgoing_with_annotation_comparison
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    # Filter by cost > 20000
    results = resolver.outgoing("TechnologyArtifact: scc/estimatedCost > 20000")
    names = results.map(&:name)

    assert_equal 2, results.length
    assert_includes names, "repo-go-large" # 50000
    assert_includes names, "repo-python"     # 25000
    refute_includes names, "repo-go-small"   # 10000
  end

  def test_relation_resolver_incoming_with_query_selector
    instance = @db.instances_by_kind("TechnologyArtifact")["repo-go-large"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    results = resolver.incoming('ApplicationComponent: activity/status == "active"')
    names = results.map(&:name)

    assert_equal 1, results.length
    assert_includes names, "MyComponent"
  end

  def test_relation_resolver_incoming_transitive_with_query_selector
    instance = @db.instances_by_kind("TechnologyArtifact")["repo-go-large"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    # Filter incoming to only ApplicationService
    results = resolver.incoming_transitive("ApplicationService:")
    names = results.map(&:name)

    assert_equal 1, results.length
    assert_includes names, "MyService"
  end

  def test_relation_resolver_query_selector_with_regex
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    # Filter by name pattern
    results = resolver.outgoing('TechnologyArtifact: name =~ "go"')
    names = results.map(&:name)

    assert_equal 2, results.length
    assert_includes names, "repo-go-large"
    assert_includes names, "repo-go-small"
  end

  # === Evaluator Tests ===

  def test_evaluator_sum
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    manager = Archsight::Annotations::ComputedManager.new(@db)
    evaluator = Archsight::Annotations::ComputedEvaluator.new(instance, @db, manager)
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    artifacts = resolver.outgoing(:TechnologyArtifact)
    result = evaluator.sum(artifacts, "scc/estimatedCost")

    # 50000 + 10000 + 25000 = 85000
    assert_in_delta(85_000.0, result)
  end

  def test_evaluator_count_instances
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    manager = Archsight::Annotations::ComputedManager.new(@db)
    evaluator = Archsight::Annotations::ComputedEvaluator.new(instance, @db, manager)
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    artifacts = resolver.outgoing(:TechnologyArtifact)
    result = evaluator.count(artifacts)

    assert_equal 3, result
  end

  def test_evaluator_count_annotation_values
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    manager = Archsight::Annotations::ComputedManager.new(@db)
    evaluator = Archsight::Annotations::ComputedEvaluator.new(instance, @db, manager)
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    artifacts = resolver.outgoing(:TechnologyArtifact)
    result = evaluator.count(artifacts, "scc/languages")

    # Only 3 have scc/languages set (repo-no-lang doesn't have it, but it's not linked)
    assert_equal 3, result
  end

  def test_evaluator_avg
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    manager = Archsight::Annotations::ComputedManager.new(@db)
    evaluator = Archsight::Annotations::ComputedEvaluator.new(instance, @db, manager)
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    artifacts = resolver.outgoing(:TechnologyArtifact)
    result = evaluator.avg(artifacts, "scc/estimatedCost")

    # (50000 + 10000 + 25000) / 3 = 28333.33...
    assert_in_delta 28_333.33, result, 1
  end

  def test_evaluator_collect
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    manager = Archsight::Annotations::ComputedManager.new(@db)
    evaluator = Archsight::Annotations::ComputedEvaluator.new(instance, @db, manager)
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    artifacts = resolver.outgoing(:TechnologyArtifact)
    result = evaluator.collect(artifacts, "scc/languages")

    assert_includes result, "Go"
    assert_includes result, "Python"
    assert_includes result, "JavaScript"
  end

  def test_evaluator_most_common
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]
    manager = Archsight::Annotations::ComputedManager.new(@db)
    evaluator = Archsight::Annotations::ComputedEvaluator.new(instance, @db, manager)
    resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, @db)

    artifacts = resolver.outgoing(:TechnologyArtifact)
    result = evaluator.most_common(artifacts, "scc/languages")

    # Go appears in repo-go-large (Go, Python) and repo-go-small (Go) = 3 times
    # Python appears in repo-go-large and repo-python = 2 times
    assert_equal "Go", result
  end

  # === Manager Tests ===

  def test_manager_caching
    manager = Archsight::Annotations::ComputedManager.new(@db)
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]

    # Create a definition
    definition = Archsight::Annotations::Computed.new("computed/test") do
      count(outgoing(:TechnologyArtifact))
    end

    # First computation
    result1 = manager.compute_for(instance, definition)

    assert_equal 3, result1

    # Second computation should use cache
    result2 = manager.compute_for(instance, definition)

    assert_equal result1, result2
  end

  def test_manager_cycle_detection
    manager = Archsight::Annotations::ComputedManager.new(@db)
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]

    # Create a definition that directly triggers cycle detection
    # by calling compute_for with itself during evaluation
    definition = Archsight::Annotations::Computed.new("computed/cycle") do
      # This simulates what happens when computed annotations depend on themselves
      # We need to trigger another compute_for call with the same key
      @manager.compute_for(@instance, @definition)
    end

    # We need to set up the evaluator context to have access to manager and definition
    # The simpler approach is to test the cycle detection directly
    cache_key = [instance.object_id, definition.key]

    # Manually add to computing set to simulate in-progress computation
    manager.instance_variable_get(:@computing).add(cache_key)

    # Now attempting to compute should detect the cycle
    assert_raises RuntimeError do
      manager.compute_for(instance, definition)
    end
  end

  def test_manager_type_coercion
    manager = Archsight::Annotations::ComputedManager.new(@db)
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]

    definition = Archsight::Annotations::Computed.new("computed/count", type: Integer) do
      count(outgoing(:TechnologyArtifact))
    end

    result = manager.compute_for(instance, definition)

    assert_instance_of Integer, result
  end

  # === Definition Tests ===

  def test_definition_creation
    definition = Archsight::Annotations::Computed.new(
      "computed/test",
      description: "Test description",
      type: Integer
    ) do
      42
    end

    assert_equal "computed/test", definition.key
    assert_equal "Test description", definition.description
    assert_equal Integer, definition.type
    assert_instance_of Proc, definition.block
  end

  def test_definition_matches
    definition = Archsight::Annotations::Computed.new("computed/test") { 42 }

    assert definition.matches?("computed/test")
    refute definition.matches?("computed/other")
  end

  # === Integration Tests ===

  def test_computed_annotation_written_to_instance
    manager = Archsight::Annotations::ComputedManager.new(@db)
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]

    definition = Archsight::Annotations::Computed.new("computed/artifact_count") do
      count(outgoing(:TechnologyArtifact))
    end

    manager.compute_for(instance, definition)

    # Value should be accessible via annotations
    assert_equal 3, instance.annotations["computed/artifact_count"]
    # And via computed_annotation_value
    assert_equal 3, instance.computed_annotation_value("computed/artifact_count")
  end

  def test_array_value_converted_to_comma_separated_string
    manager = Archsight::Annotations::ComputedManager.new(@db)
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]

    definition = Archsight::Annotations::Computed.new("computed/languages_test") do
      collect(outgoing(:TechnologyArtifact), "scc/languages")
    end

    result = manager.compute_for(instance, definition)

    # Result in memory should still be an array
    assert_instance_of Array, result

    # But stored value should be comma-separated string
    stored = instance.annotations["computed/languages_test"]

    assert_instance_of String, stored
    assert_includes stored, ",", "Expected comma-separated string, got: #{stored}"
  end

  def test_nil_value_not_written_to_annotations
    manager = Archsight::Annotations::ComputedManager.new(@db)
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]

    # Create a definition that returns nil (no matching data)
    definition = Archsight::Annotations::Computed.new("computed/nil_test") do
      first(outgoing(:TechnologyArtifact), "nonexistent/annotation")
    end

    result = manager.compute_for(instance, definition)

    # Result should be nil
    assert_nil result
    # Annotation should NOT be written to instance
    refute instance.annotations.key?("computed/nil_test")
  end

  def test_empty_array_not_written_to_annotations
    manager = Archsight::Annotations::ComputedManager.new(@db)
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]

    # Create a definition that returns empty array
    definition = Archsight::Annotations::Computed.new("computed/empty_test") do
      collect(outgoing(:TechnologyArtifact), "nonexistent/annotation")
    end

    result = manager.compute_for(instance, definition)

    # Result should be empty array
    assert_empty result
    # Annotation should NOT be written to instance
    refute instance.annotations.key?("computed/empty_test")
  end

  def test_meaningful_value_written_to_annotations
    manager = Archsight::Annotations::ComputedManager.new(@db)
    instance = @db.instances_by_kind("ApplicationComponent")["MyComponent"]

    # Create a definition that returns a meaningful value
    definition = Archsight::Annotations::Computed.new("computed/meaningful_test") do
      count(outgoing(:TechnologyArtifact))
    end

    result = manager.compute_for(instance, definition)

    # Result should be meaningful (3 artifacts)
    assert_equal 3, result
    # Annotation SHOULD be written to instance
    assert instance.annotations.key?("computed/meaningful_test")
    assert_equal 3, instance.annotations["computed/meaningful_test"]
  end

  # === ApplicationComponent Open-Source Filtering Tests ===

  def test_activity_commits_skips_open_source_repos
    # Set up component with mixed repos (some open-source)
    @db.add_instance("TechnologyArtifact", "oss-repo", {
                       "artifact/type" => "repo",
                       "repository/visibility" => "open-source",
                       "activity/commits" => "10,20,30"
                     })
    @db.add_instance("TechnologyArtifact", "private-repo", {
                       "artifact/type" => "repo",
                       "activity/commits" => "5,10,15"
                     })

    component = @db.add_instance("ApplicationComponent", "MixedComponent", {})
    @db.link("ApplicationComponent", "MixedComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "oss-repo")
    @db.link("ApplicationComponent", "MixedComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "private-repo")

    manager = Archsight::Annotations::ComputedManager.new(@db)

    # Find the activity/commits computed annotation definition for ApplicationComponent
    definition = Archsight::Resources::ApplicationComponent.computed_annotations.find { |d| d.key == "activity/commits" }
    skip("activity/commits computed annotation not found") unless definition

    result = manager.compute_for(component, definition)

    # Should only include private-repo's commits, not oss-repo
    assert_equal "5,10,15", result
  end

  def test_activity_commits_with_empty_commits_annotation
    component = @db.add_instance("ApplicationComponent", "EmptyCommitsComponent", {})
    @db.add_instance("TechnologyArtifact", "empty-commits-repo", {
                       "artifact/type" => "repo",
                       "activity/commits" => ""
                     })
    @db.link("ApplicationComponent", "EmptyCommitsComponent", :realizedThrough, :technologyArtifacts,
             "TechnologyArtifact", "empty-commits-repo")

    manager = Archsight::Annotations::ComputedManager.new(@db)
    definition = Archsight::Resources::ApplicationComponent.computed_annotations.find { |d| d.key == "activity/commits" }
    skip("activity/commits computed annotation not found") unless definition

    result = manager.compute_for(component, definition)

    assert_nil result
  end

  def test_activity_commits_with_different_array_lengths
    # Create artifacts with different length commit arrays (simulating repos started at different times)
    @db.add_instance("TechnologyArtifact", "old-repo", {
                       "artifact/type" => "repo",
                       "activity/commits" => "1,2,3,4,5"
                     })
    @db.add_instance("TechnologyArtifact", "new-repo", {
                       "artifact/type" => "repo",
                       "activity/commits" => "10,20"
                     })

    component = @db.add_instance("ApplicationComponent", "MultiRepoComponent", {})
    @db.link("ApplicationComponent", "MultiRepoComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "old-repo")
    @db.link("ApplicationComponent", "MultiRepoComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "new-repo")

    manager = Archsight::Annotations::ComputedManager.new(@db)
    definition = Archsight::Resources::ApplicationComponent.computed_annotations.find { |d| d.key == "activity/commits" }
    skip("activity/commits computed annotation not found") unless definition

    result = manager.compute_for(component, definition)

    # new-repo should be padded with zeros at the front: [0,0,0,10,20]
    # Then summed with old-repo: [1,2,3,4,5] + [0,0,0,10,20] = [1,2,3,14,25]
    assert_equal "1,2,3,14,25", result
  end

  def test_activity_created_at_skips_open_source_and_parses_dates
    @db.add_instance("TechnologyArtifact", "oss-date-repo", {
                       "artifact/type" => "repo",
                       "repository/visibility" => "open-source",
                       "activity/createdAt" => "2020-01-01T00:00:00Z"
                     })
    @db.add_instance("TechnologyArtifact", "private-date-repo", {
                       "artifact/type" => "repo",
                       "activity/createdAt" => "2022-06-15T12:00:00Z"
                     })

    component = @db.add_instance("ApplicationComponent", "DateComponent", {})
    @db.link("ApplicationComponent", "DateComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "oss-date-repo")
    @db.link("ApplicationComponent", "DateComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "private-date-repo")

    manager = Archsight::Annotations::ComputedManager.new(@db)
    definition = Archsight::Resources::ApplicationComponent.computed_annotations.find do |d|
      d.key == "activity/createdAt"
    end
    skip("activity/createdAt computed annotation not found") unless definition

    result = manager.compute_for(component, definition)

    # Should only consider private-date-repo, not oss-date-repo
    assert_kind_of Time, result
    assert_equal 2022, result.year
  end

  def test_activity_created_at_handles_invalid_dates
    @db.add_instance("TechnologyArtifact", "invalid-date-repo", {
                       "artifact/type" => "repo",
                       "activity/createdAt" => "not-a-valid-date"
                     })

    component = @db.add_instance("ApplicationComponent", "InvalidDateComponent", {})
    @db.link("ApplicationComponent", "InvalidDateComponent", :realizedThrough, :technologyArtifacts,
             "TechnologyArtifact", "invalid-date-repo")

    manager = Archsight::Annotations::ComputedManager.new(@db)
    definition = Archsight::Resources::ApplicationComponent.computed_annotations.find do |d|
      d.key == "activity/createdAt"
    end
    skip("activity/createdAt computed annotation not found") unless definition

    # Should handle invalid date gracefully and return nil
    result = manager.compute_for(component, definition)

    assert_nil result
  end

  def test_activity_contributors_6m_skips_open_source
    @db.add_instance("TechnologyArtifact", "oss-contrib-repo", {
                       "artifact/type" => "repo",
                       "repository/visibility" => "open-source",
                       "activity/contributors/6m" => "100"
                     })
    @db.add_instance("TechnologyArtifact", "private-contrib-repo", {
                       "artifact/type" => "repo",
                       "activity/contributors/6m" => "5"
                     })

    component = @db.add_instance("ApplicationComponent", "ContribComponent", {})
    @db.link("ApplicationComponent", "ContribComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "oss-contrib-repo")
    @db.link("ApplicationComponent", "ContribComponent", :realizedThrough, :technologyArtifacts, "TechnologyArtifact",
             "private-contrib-repo")

    manager = Archsight::Annotations::ComputedManager.new(@db)
    definition = Archsight::Resources::ApplicationComponent.computed_annotations.find do |d|
      d.key == "activity/contributors/6m"
    end
    skip("activity/contributors/6m computed annotation not found") unless definition

    result = manager.compute_for(component, definition)

    # Should only sum private-contrib-repo's contributors (5), not oss-contrib-repo (100)
    assert_equal 5, result
  end

  def test_activity_contributors_returns_nil_for_zero_total
    @db.add_instance("TechnologyArtifact", "zero-contrib-repo", {
                       "artifact/type" => "repo",
                       "activity/contributors/6m" => "0"
                     })

    component = @db.add_instance("ApplicationComponent", "ZeroContribComponent", {})
    @db.link("ApplicationComponent", "ZeroContribComponent", :realizedThrough, :technologyArtifacts,
             "TechnologyArtifact", "zero-contrib-repo")

    manager = Archsight::Annotations::ComputedManager.new(@db)
    definition = Archsight::Resources::ApplicationComponent.computed_annotations.find do |d|
      d.key == "activity/contributors/6m"
    end
    skip("activity/contributors/6m computed annotation not found") unless definition

    result = manager.compute_for(component, definition)

    # Zero total should return nil
    assert_nil result
  end

  # Mock Database class for testing (based on evaluator_test.rb)
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
  end
end
