# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class BusinessRoleTest < Minitest::Test
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Security
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessRole
    metadata:
      name: Role:ControlOwner
      annotations:
        role/id: CO
        role/type: owner
    spec:
      performedBy:
        businessActors:
          - Team:Security
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessControl
    metadata:
      name: Control:AccessReview
    spec:
      ownedBy:
        businessRoles:
          - Role:ControlOwner
      executedBy:
        businessActors:
          - Team:Security
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessProcess
    metadata:
      name: Process:Onboarding
    spec:
      performedBy:
        businessRoles:
          - Role:ControlOwner
        businessActors:
          - Team:Security
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationAssessment
    metadata:
      name: Risk:Leak
      annotations:
        assessment/type: risk
    spec:
      ownedBy:
        businessRoles:
          - Role:ControlOwner
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationWorkPackage
    metadata:
      name: WorkPackage:Fix
    spec:
      ownedBy:
        businessRoles:
          - Role:ControlOwner
      performedBy:
        businessRoles:
          - Role:ControlOwner
  YAML

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false)
      db.reload!
      yield db
    end
  end

  def changed(from, to)
    assert_includes RESOURCES, from
    RESOURCES.sub(from, to)
  end

  def annotation(key)
    Archsight::Resources::BusinessRole.annotations.find { |a| a.key == key }
  end

  def test_is_a_business_layer_kind
    assert_equal "business", Archsight::Resources["BusinessRole"].layer
  end

  def test_the_chain_process_role_actor_loads_and_links_both_ways
    with_db do |db|
      process = db.instance_by_kind("BusinessProcess", "Process:Onboarding")
      role = db.instance_by_kind("BusinessRole", "Role:ControlOwner")
      actor = db.instance_by_kind("BusinessActor", "Team:Security")

      assert_equal [role], process.relations(:performedBy, :businessRoles)
      assert_equal [actor], role.relations(:performedBy, :businessActors)
      assert_equal [process], role.references_grouped.dig("BusinessProcess", :performedBy)
      assert_equal [role], actor.references_grouped.dig("BusinessRole", :performedBy)
    end
  end

  def test_a_process_can_still_point_at_an_actor_directly
    with_db do |db|
      process = db.instance_by_kind("BusinessProcess", "Process:Onboarding")

      assert_equal ["Team:Security"], process.relations(:performedBy, :businessActors).map(&:name)
    end
  end

  def test_controls_assessments_and_work_packages_are_owned_by_a_role
    with_db do |db|
      role = db.instance_by_kind("BusinessRole", "Role:ControlOwner")
      grouped = role.references_grouped

      assert_equal %w[Control:AccessReview], grouped.dig("BusinessControl", :ownedBy).map(&:name)
      assert_equal %w[Risk:Leak], grouped.dig("MotivationAssessment", :ownedBy).map(&:name)
      assert_equal %w[WorkPackage:Fix], grouped.dig("ImplementationWorkPackage", :ownedBy).map(&:name)
      assert_equal %w[WorkPackage:Fix], grouped.dig("ImplementationWorkPackage", :performedBy).map(&:name)
    end
  end

  def test_a_role_cannot_point_at_a_process
    yaml = changed("  performedBy:\n    businessActors:\n      - Team:Security\n---\napiVersion: architecture/v1alpha1\nkind: BusinessControl",
                   "  performedBy:\n    businessProcesses:\n      - Process:Onboarding\n---\napiVersion: architecture/v1alpha1\nkind: BusinessControl")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_role_type_only_accepts_known_values
    assert annotation("role/type").valid?("executor")
    refute annotation("role/type").valid?("boss")
  end

  def test_summary_annotations_stay_within_the_limit
    summary = Archsight::Resources::BusinessRole.annotations.select(&:summary?).map(&:key)

    assert_equal %w[role/id role/type], summary
  end
end
