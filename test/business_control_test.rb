# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class BusinessControlTest < Minitest::Test
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Operations
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Management
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessRequirement
    metadata:
      name: Requirement:Documentation
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ComplianceEvidence
    metadata:
      name: Evidence:ModelHistory
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessControl
    metadata:
      name: Control:Documentation
      annotations:
        control/id: DOC-01
        control/status: implemented
        control/frequency: event-based
        control/last-review: '2026-09-01'
        control/next-review: '2027-09-01'
    spec:
      ownedBy:
        businessActors:
          - Team:Management
      executedBy:
        businessActors:
          - Team:Operations
      satisfies:
        businessRequirements:
          - Requirement:Documentation
      evidencedBy:
        complianceEvidences:
          - Evidence:ModelHistory
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessProcess
    metadata:
      name: Process:Change
    spec:
      guidedBy:
        businessControls:
          - Control:Documentation
  YAML

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false)
      db.reload!
      yield db
    end
  end

  # RESOURCES with `from` replaced; fails when it is not there, so a negative test cannot pass by testing nothing
  def changed(from, to)
    assert_includes RESOURCES, from
    RESOURCES.sub(from, to)
  end

  def annotation(key)
    Archsight::Resources::BusinessControl.annotations.find { |a| a.key == key }
  end

  def test_is_a_business_layer_kind
    assert_equal "business", Archsight::Resources["BusinessControl"].layer
  end

  def test_process_is_guided_by_control_and_control_lists_the_process
    with_db do |db|
      process = db.instance_by_kind("BusinessProcess", "Process:Change")
      control = db.instance_by_kind("BusinessControl", "Control:Documentation")

      assert_equal [control], process.relations(:guidedBy, :businessControls)
      assert_equal [process], control.references_grouped.dig("BusinessProcess", :guidedBy)
    end
  end

  def test_owner_and_executors_link_to_business_actors
    with_db do |db|
      control = db.instance_by_kind("BusinessControl", "Control:Documentation")
      owner = db.instance_by_kind("BusinessActor", "Team:Management")
      executor = db.instance_by_kind("BusinessActor", "Team:Operations")

      assert_equal [owner], control.relations(:ownedBy, :businessActors)
      assert_equal [executor], control.relations(:executedBy, :businessActors)
      assert_equal [control], owner.references_grouped.dig("BusinessControl", :ownedBy)
      assert_equal [control], executor.references_grouped.dig("BusinessControl", :executedBy)
    end
  end

  def test_satisfies_requirements_and_is_evidenced_by_evidence
    with_db do |db|
      control = db.instance_by_kind("BusinessControl", "Control:Documentation")

      assert_equal ["Requirement:Documentation"], control.relations(:satisfies, :businessRequirements).map(&:name)
      assert_equal ["Evidence:ModelHistory"], control.relations(:evidencedBy, :complianceEvidences).map(&:name)
    end
  end

  def test_owner_must_exist_as_business_actor
    yaml = changed("- Team:Management", "- Team:Missing")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_process_cannot_use_the_verbs_of_a_control
    yaml = changed("guidedBy:\n    businessControls:\n      - Control:Documentation",
                   "ownedBy:\n    businessActors:\n      - Team:Management")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_control_cannot_guide_a_process
    yaml = changed("  satisfies:\n    businessRequirements:\n      - Requirement:Documentation",
                   "  guidedBy:\n    businessControls:\n      - Control:Documentation")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_status_and_frequency_only_accept_known_values
    assert annotation("control/status").valid?("partial")
    refute annotation("control/status").valid?("done")
    assert annotation("control/frequency").valid?("quarterly")
    refute annotation("control/frequency").valid?("sometimes")
  end

  def test_review_dates_are_iso_dates
    assert annotation("control/last-review").valid?("2026-09-01")
    assert annotation("control/next-review").valid?("2027-09-01T09:30:00Z")
    refute annotation("control/next-review").valid?("next year")
  end

  def test_summary_annotations_stay_within_the_limit
    summary = Archsight::Resources::BusinessControl.annotations.select(&:summary?).map(&:key)

    assert_equal %w[control/id control/status control/frequency], summary
  end
end
