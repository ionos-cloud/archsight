# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ImplementationLayerTest < Minitest::Test
  KINDS = %w[ImplementationWorkPackage ImplementationDeliverable ImplementationEvent ImplementationPlateau
             ImplementationGap].freeze
  LAYERS = %w[strategy motivation business application technology implementation other].freeze

  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Security
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationAssessment
    metadata:
      name: Risk:Intrusion
      annotations:
        assessment/type: risk
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ComplianceEvidence
    metadata:
      name: Evidence:Firewall
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationPlateau
    metadata:
      name: Plateau:Baseline
      annotations:
        plateau/type: baseline
    spec:
      triggers:
        implementationPlateaus:
          - Plateau:Target
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationPlateau
    metadata:
      name: Plateau:Target
      annotations:
        plateau/type: target
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationGap
    metadata:
      name: Gap:Firewall
      annotations:
        gap/status: open
    spec:
      compares:
        implementationPlateaus:
          - Plateau:Baseline
          - Plateau:Target
      closedBy:
        implementationWorkPackages:
          - WorkPackage:Firewall
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationWorkPackage
    metadata:
      name: WorkPackage:Firewall
      annotations:
        workpackage/type: remediation
        workpackage/status: in-progress
        workpackage/due: '2026-12-15'
    spec:
      ownedBy:
        businessActors:
          - Team:Security
      mitigates:
        motivationAssessments:
          - Risk:Intrusion
      realizes:
        implementationDeliverables:
          - Deliverable:FirewallRules
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationDeliverable
    metadata:
      name: Deliverable:FirewallRules
      annotations:
        deliverable/type: evidence
    spec:
      realizes:
        implementationPlateaus:
          - Plateau:Target
        complianceEvidences:
          - Evidence:Firewall
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationEvent
    metadata:
      name: Milestone:GoLive
      annotations:
        event/type: go-live
        event/occurred: '2026-12-15'
    spec:
      triggers:
        implementationWorkPackages:
          - WorkPackage:Firewall
  YAML

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false)
      db.reload!
      yield db
    end
  end

  def annotation(kind, key)
    Archsight::Resources[kind].annotations.find { |a| a.key == key }
  end

  def test_all_five_kinds_are_on_the_implementation_layer
    KINDS.each { |kind| assert_equal "implementation", Archsight::Resources[kind].layer, kind }
  end

  def test_the_migration_chain_loads_and_links_both_ways
    with_db do |db|
      work = db.instance_by_kind("ImplementationWorkPackage", "WorkPackage:Firewall")
      deliverable = db.instance_by_kind("ImplementationDeliverable", "Deliverable:FirewallRules")
      gap = db.instance_by_kind("ImplementationGap", "Gap:Firewall")
      target = db.instance_by_kind("ImplementationPlateau", "Plateau:Target")

      assert_equal [deliverable], work.relations(:realizes, :implementationDeliverables)
      assert_equal ["Risk:Intrusion"], work.relations(:mitigates, :motivationAssessments).map(&:name)
      assert_equal [work], gap.relations(:closedBy, :implementationWorkPackages)
      assert_equal %w[Plateau:Baseline Plateau:Target], gap.relations(:compares, :implementationPlateaus).map(&:name).sort
      assert_equal %w[ImplementationDeliverable ImplementationGap ImplementationPlateau],
                   target.references_grouped.keys.sort
    end
  end

  def test_a_deliverable_realizes_evidence_and_the_event_triggers_the_work
    with_db do |db|
      deliverable = db.instance_by_kind("ImplementationDeliverable", "Deliverable:FirewallRules")
      work = db.instance_by_kind("ImplementationWorkPackage", "WorkPackage:Firewall")

      assert_equal ["Evidence:Firewall"], deliverable.relations(:realizes, :complianceEvidences).map(&:name)
      assert_equal ["Milestone:GoLive"], work.references_grouped.dig("ImplementationEvent", :triggers).map(&:name)
    end
  end

  def test_a_work_package_cannot_compare_plateaus
    yaml = RESOURCES.sub("  mitigates:\n    motivationAssessments:\n      - Risk:Intrusion",
                         "  compares:\n    implementationPlateaus:\n      - Plateau:Target")

    refute_equal RESOURCES, yaml
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_enums_and_dates_are_checked
    assert annotation("ImplementationWorkPackage", "workpackage/type").valid?("remediation")
    refute annotation("ImplementationWorkPackage", "workpackage/type").valid?("hobby")
    assert annotation("ImplementationPlateau", "plateau/type").valid?("transition")
    refute annotation("ImplementationGap", "gap/status").valid?("maybe")
    assert annotation("ImplementationWorkPackage", "workpackage/due").valid?("2026-12-15")
    refute annotation("ImplementationWorkPackage", "workpackage/due").valid?("soon")
  end

  def test_every_kind_has_a_known_layer_and_its_own_icon
    classes = Archsight::Resources.resource_classes.values

    classes.each { |klass| assert_includes LAYERS, klass.layer, klass.name }
    duplicates = classes.group_by(&:icon).select { |_icon, group| group.size > 1 }

    assert_empty(duplicates.transform_values { |group| group.map(&:name) })
  end
end
