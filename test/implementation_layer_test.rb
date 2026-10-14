# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ImplementationLayerTest < Minitest::Test
  KINDS = %w[ImplementationWorkPackage ImplementationDeliverable ImplementationEvent ImplementationPlateau
             ImplementationGap].freeze

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
    spec:
      mitigatedBy:
        implementationWorkPackages:
          - WorkPackage:Firewall
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
      assert_equal ["Risk:Intrusion"], work.references_grouped.dig("MotivationAssessment", :mitigatedBy).map(&:name)
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
    yaml = RESOURCES.sub("  realizes:\n    implementationDeliverables:\n      - Deliverable:FirewallRules",
                         "  compares:\n    implementationPlateaus:\n      - Plateau:Target")

    refute_equal RESOURCES, yaml
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  PLATEAU_TECH = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: Svc:Old
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: Svc:New
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologySystemSoftware
    metadata:
      name: Soft:New
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyArtifact
    metadata:
      name: Art:New
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Ops
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationPlateau
    metadata:
      name: Plateau:Past
    spec:
      contains:
        technologyServices:
          - Svc:Old
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationPlateau
    metadata:
      name: Plateau:Now
    spec:
      contains:
        technologyServices:
          - Svc:New
        technologySystemSoftware:
          - Soft:New
        technologyArtifacts:
          - Art:New
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationGap
    metadata:
      name: Gap:Platform
    spec:
      compares:
        implementationPlateaus:
          - Plateau:Past
          - Plateau:Now
  YAML

  def test_a_plateau_contains_technology_services_system_software_and_artifacts
    with_db(PLATEAU_TECH) do |db|
      now = db.instance_by_kind("ImplementationPlateau", "Plateau:Now")

      assert_equal ["Svc:New"], now.relations(:contains, :technologyServices).map(&:name)
      assert_equal ["Soft:New"], now.relations(:contains, :technologySystemSoftware).map(&:name)
      assert_equal ["Art:New"], now.relations(:contains, :technologyArtifacts).map(&:name)
      assert_equal %w[TechnologyArtifact TechnologyService TechnologySystemSoftware],
                   now.relations_grouped["contains"].keys.sort
    end
  end

  def test_technology_elements_show_in_which_plateau_they_are
    with_db(PLATEAU_TECH) do |db|
      %w[TechnologyService:Svc:Old TechnologySystemSoftware:Soft:New TechnologyArtifact:Art:New].each do |ref|
        kind, name = ref.split(":", 2)
        plateaus = db.instance_by_kind(kind, name).references_grouped.dig("ImplementationPlateau", :contains)

        assert_equal 1, plateaus.size, ref
      end
    end
  end

  def test_a_gap_compares_plateaus_with_technology_elements
    with_db(PLATEAU_TECH) do |db|
      gap = db.instance_by_kind("ImplementationGap", "Gap:Platform")
      past, now = gap.relations(:compares, :implementationPlateaus).sort_by(&:name).reverse
      names = ->(plateau) { plateau.relations(:contains, :technologyServices).map(&:name) }

      assert_equal ["Svc:Old"], names.call(past)
      assert_equal ["Svc:New"], names.call(now)
      assert_equal ["Svc:New"], names.call(now) - names.call(past)
    end
  end

  def test_a_plateau_rejects_the_wrong_kind_for_the_technology_relations
    %w[technologyServices technologySystemSoftware technologyArtifacts].each do |key|
      yaml = "#{PLATEAU_TECH}---\napiVersion: architecture/v1alpha1\nkind: ImplementationPlateau\nmetadata:\n  name: Plateau:Bad\n" \
             "spec:\n  contains:\n    #{key}:\n      - Team:Ops\n"

      assert_raises(Archsight::ResourceError, key) { with_db(yaml) { nil } }
    end
  end

  def test_the_platform_migration_example_loads_with_three_plateaus
    db = Archsight::Database.new(File.expand_path("../examples/archsight", __dir__), verbose: false)
    db.reload!
    plateaus = %w[Past Current Target].map { |n| db.instance_by_kind("ImplementationPlateau", "Plateau:Platform:#{n}") }

    assert(plateaus.all? { |p| p.relations(:contains, :technologyServices).any? })
    assert_equal %w[Plateau:Platform:Current], plateaus[0].relations(:triggers, :implementationPlateaus).map(&:name)
    assert_equal %w[Platform:Container:Runtime Platform:Legacy:Runtime],
                 plateaus[1].relations(:contains, :technologySystemSoftware).map(&:name).sort
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

    classes.each { |klass| assert_includes Archsight::Resources::LAYERS, klass.layer, klass.name }
    duplicates = classes.group_by(&:icon).select { |_icon, group| group.size > 1 }

    assert_empty(duplicates.transform_values { |group| group.map(&:name) })
  end

  def test_a_kind_cannot_declare_an_unknown_layer
    error = assert_raises(ArgumentError) { Class.new(Archsight::Resources::Base) { layer "physical" } }
    assert_includes error.message, "physical"
  end
end
