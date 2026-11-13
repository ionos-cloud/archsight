# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "rack/test"
require "archsight/web/application"
require "json"

# Grouping (ArchiMate composite element): aggregates or composes resources of every kind, groupings included
class GroupingTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Archsight::Web::Application
  end

  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Payments:API
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessProcess
    metadata:
      name: Refund Handling
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: DataObject
    metadata:
      name: Payment
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: Grouping
    metadata:
      name: Domain:Payments
    spec:
      aggregates:
        applicationComponents:
          - Payments:API
        groupings:
          - Domain:Refunds
      composedOf:
        dataObjects:
          - Payment
    ---
    apiVersion: architecture/v1alpha1
    kind: Grouping
    metadata:
      name: Domain:Refunds
    spec:
      aggregates:
        businessProcesses:
          - Refund Handling
        applicationComponents:
          - Payments:API
  YAML

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def test_kind_is_a_composite_in_the_other_layer
    klass = Archsight::Resources["Grouping"]

    assert_equal "other", klass.layer
    assert_equal "square-dashed", klass.icon
  end

  def test_declares_both_verbs_towards_every_kind_itself_included
    declared = Archsight::Resources::Grouping.declared_relations

    Archsight::Resources::Grouping::MEMBER_VERBS.each do |verb|
      targets = declared.select { |v, _, _| v == verb }.map(&:last)

      assert_equal Archsight::Resources.resource_classes.keys.sort, targets.sort, "#{verb} must reach every kind"
    end
    assert_includes declared, [:aggregates, :groupings, "Grouping"]
  end

  def test_declaring_members_again_does_not_duplicate
    before = Archsight::Resources::Grouping.declared_relations.dup
    Archsight::Resources::Grouping.declare_members!

    assert_equal before, Archsight::Resources::Grouping.declared_relations
  end

  # A grouping uses the key the rest of the model already uses for a kind, so members are written the same way
  # everywhere (kinds only reached through a shared key such as technologyComponents are skipped)
  def test_relation_key_matches_the_keys_already_in_use
    used = Hash.new { |h, k| h[k] = [] }
    Archsight::Resources.resource_classes.each do |name, klass|
      next if name == "Grouping"

      klass.declared_relations.each { |_, key, kind| used[kind.to_s] << key.to_s }
    end

    used.each do |kind, keys|
      next if keys.uniq == ["technologyComponents"]

      assert_includes keys, Archsight::Resources.relation_key(kind), "key of #{kind}"
    end
  end

  def test_relation_key_plurals
    assert_equal "applicationComponents", Archsight::Resources.relation_key("ApplicationComponent")
    assert_equal "businessProcesses", Archsight::Resources.relation_key("BusinessProcess")
    assert_equal "strategyCapabilities", Archsight::Resources.relation_key("StrategyCapability")
    assert_equal "groupings", Archsight::Resources.relation_key("Grouping")
    assert_equal "analyses", Archsight::Resources.relation_key("Analysis")
  end

  def test_members_of_every_kind_and_nested_groups_resolve
    with_db do |db|
      payments = db.instance_by_kind("Grouping", "Domain:Payments")
      grouped = payments.relations_grouped

      assert_equal ["Payments:API"], grouped["aggregates"]["ApplicationComponent"].map(&:name)
      assert_equal ["Domain:Refunds"], grouped["aggregates"]["Grouping"].map(&:name)
      assert_equal ["Payment"], grouped["composedOf"]["DataObject"].map(&:name)
    end
  end

  def test_a_member_lists_every_group_it_is_in
    with_db do |db|
      api = db.instance_by_kind("ApplicationComponent", "Payments:API")
      groups = api.references_grouped["Grouping"][:aggregates].map(&:name)

      assert_equal %w[Domain:Payments Domain:Refunds], groups.sort
    end
  end

  def test_query_follows_membership
    with_db do |db|
      names = db.query("ApplicationComponent: <- Grouping").map(&:name)

      assert_includes names, "Payments:API"
    end
  end

  def test_example_model_lints_clean
    assert_empty(with_db { |db| Archsight::Linter.new(db).validate })
  end

  def test_a_group_containing_itself_is_a_cycle
    yaml = <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: Grouping
      metadata:
        name: Group:A
      spec:
        aggregates:
          groupings: [Group:B]
      ---
      apiVersion: architecture/v1alpha1
      kind: Grouping
      metadata:
        name: Group:B
      spec:
        aggregates:
          groupings: [Group:A]
    YAML
    errors = with_db(yaml) { |db| Archsight::Linter.new(db).validate }

    assert_match(/Grouping 'Group:\w' is part of a cycle of aggregates relations/, errors.join("\n"))
  end

  def test_summary_of_a_member_names_its_groups
    with_db do |db|
      text = Archsight::Summary::Builder.new(db).call(db.instance_by_kind("ApplicationComponent", "Payments:API"))

      assert_includes text, "Groups"
      assert_includes text, "[[Grouping/Domain:Payments]]"
    end
  end

  def test_summary_of_a_grouping_lists_its_members
    with_db do |db|
      text = Archsight::Summary::Builder.new(db).call(db.instance_by_kind("Grouping", "Domain:Payments"))

      assert_includes text, "Members"
      assert_includes text, "[[ApplicationComponent/Payments:API]]"
      assert_includes text, "[[DataObject/Payment]]"
    end
  end

  def test_template_shows_a_few_member_kinds_only
    spec = YAML.safe_load(Archsight::Template.generate("Grouping"))["spec"]

    assert_equal %w[aggregates composedOf], spec.keys
    assert_equal %w[applicationComponents businessProcesses groupings], spec["aggregates"].keys
  end

  def test_api_shows_the_example_grouping
    Archsight.resources_dir = File.expand_path("../examples/archsight", __dir__)
    Archsight::Web::Application.database.reload!
    get "/api/v1/kinds/Grouping/instances/Domain:Payments"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "Domain:Payments:Refunds"
    assert_includes last_response.body, "Payments:API"
  end
end
