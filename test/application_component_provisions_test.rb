# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# An ApplicationComponent provisions the TechnologyServices it creates (issue #206): the relation is written on the
# component and points down, like every relation, so the service never points back up
class ApplicationComponentProvisionsTest < Minitest::Test
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: Cluster:Product
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: Cluster:Platform
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Operator
    spec:
      provisions:
        technologyServices: [Cluster:Product]
      servedBy:
        technologyServices: [Cluster:Platform]
  YAML

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def test_the_component_provisions_services_and_the_service_lists_it_as_incoming
    with_db do |db|
      operator = db.instance_by_kind("ApplicationComponent", "Operator")
      cluster = db.instance_by_kind("TechnologyService", "Cluster:Product")

      assert_equal ["Cluster:Product"], operator.relations(:provisions, :technologyServices).map(&:name)
      assert_equal ["Operator"], cluster.references_grouped.dig("ApplicationComponent", :provisions).map(&:name)
    end
  end

  def test_provisions_is_not_where_the_component_runs
    with_db do |db|
      platform = db.instance_by_kind("TechnologyService", "Cluster:Platform")
      product = db.instance_by_kind("TechnologyService", "Cluster:Product")

      assert_equal ["Operator"], platform.references_grouped.dig("ApplicationComponent", :servedBy).map(&:name)
      assert_nil product.references_grouped.dig("ApplicationComponent", :servedBy)
    end
  end

  def test_the_relation_points_down_only
    assert_includes Archsight::Resources["ApplicationComponent"].declared_relations, %i[provisions technologyServices TechnologyService]
    refute(Archsight::Resources["TechnologyService"].declared_relations.any? { |verb, _, _| %i[provisions provisionedBy].include?(verb) })
  end

  def test_a_provisioner_that_also_runs_in_the_service_it_builds_is_no_cycle
    yaml = RESOURCES.sub("technologyServices: [Cluster:Platform]", "technologyServices: [Cluster:Product]")

    refute_equal RESOURCES, yaml
    with_db(yaml) { |db| assert_empty Archsight::Linter.new(db).validate }
  end

  def test_the_impact_of_a_provisioner_is_what_it_reaches
    with_db do |db|
      operator = db.instance_by_kind("ApplicationComponent", "Operator")
      reached = Archsight::Annotations::ComputedRelationResolver.new(operator, db).outgoing_transitive(:TechnologyService).map(&:name)

      assert_equal %w[Cluster:Platform Cluster:Product], reached.sort
    end
  end

  def test_a_target_that_is_not_a_technology_service_is_rejected
    yaml = RESOURCES.sub("provisions:\n    technologyServices: [Cluster:Product]", "provisions:\n    technologyServices: [Operator]")

    refute_equal RESOURCES, yaml
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_a_service_cannot_declare_the_relation_upwards
    yaml = RESOURCES.sub("name: Cluster:Product\nspec: {}", "name: Cluster:Product\nspec:\n  provisionedBy:\n    applicationComponents: [Operator]")

    refute_equal RESOURCES, yaml
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_the_example_operator_provisions_the_payments_cluster
    db = Archsight::Database.new(File.expand_path("../examples/archsight", __dir__), verbose: false, compute_annotations: false)
    db.reload!
    cluster = db.instance_by_kind("TechnologyService", "Payments:Cluster")

    assert_equal ["Payments:ClusterOperator"], cluster.references_grouped.dig("ApplicationComponent", :provisions).map(&:name)
    assert_equal %w[Payments:API Refunds:Worker], cluster.references_grouped.dig("ApplicationComponent", :servedBy).map(&:name).sort
  end
end
