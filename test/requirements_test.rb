# frozen_string_literal: true

require_relative "test_helper"

class RequirementsTest < Minitest::Test
  YAML_DOC = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Req:A
      annotations:
        requirement/priority: must
        requirement/story: Story **A**
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Req:B
      annotations:
        requirement/priority: should
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Req:C
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Req:Must0
      annotations:
        requirement/priority: must
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Backup
    spec:
      realizes:
        motivationRequirements: [Req:A]
      partiallyRealizes:
        motivationRequirements: [Req:B]
      plans:
        motivationRequirements: [Req:C, Req:Must0]
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Restore
    spec:
      plans:
        motivationRequirements: [Req:A, Req:B]
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Unrelated
  YAML

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "all.yaml"), YAML_DOC)
    @db = Archsight::Database.new(@dir)
    @db.reload!
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def collect(**) = Archsight::Requirements.collect(@db, of: "ApplicationService:", **)

  def find(entries, name) = entries.find { |e| e[:name] == name }

  def names(entries) = entries.map { |e| e[:name] }

  def test_one_entry_per_requirement_with_the_status_of_each_verb
    entries = collect

    assert_equal %w[Req:A Req:Must0 Req:B Req:C], names(entries)
    assert_equal "implemented", find(entries, "Req:A")[:status]
    assert_equal "partial", find(entries, "Req:B")[:status]
    assert_equal "planned", find(entries, "Req:C")[:status]
  end

  def test_requirement_of_several_resources_gets_the_best_status_and_lists_them
    a = find(collect, "Req:A")

    assert_equal "implemented", a[:status]
    assert_equal [{ kind: "ApplicationService", name: "Backup", status: "implemented" },
                  { kind: "ApplicationService", name: "Restore", status: "planned" }], a[:by]
  end

  def test_carries_priority_and_story
    a = find(collect, "Req:A")

    assert_equal "must", a[:priority]
    assert_equal "Story **A**", a[:story]
    assert_nil find(collect, "Req:C")[:priority]
  end

  def test_sorted_by_priority_then_name
    priorities = collect.map { |e| e[:priority] || "none" }

    assert_equal %w[must must should none], priorities
  end

  def test_selection_limits_the_resources
    entries = Archsight::Requirements.collect(@db, of: 'ApplicationService: name == "Restore"')

    assert_equal %w[Req:A Req:B], names(entries)
    assert_equal [%w[Restore]], entries.map { |e| e[:by].map { |b| b[:name] } }.uniq
    assert_equal "planned", find(entries, "Req:A")[:status]
  end

  def test_priority_and_status_filters
    assert_equal %w[Req:A Req:Must0], names(collect(priority: ["must"]))
    assert_equal %w[Req:A Req:B], names(collect(priority: %w[must should], status: %w[implemented partial]))
    assert_equal %w[Req:Must0 Req:C], names(collect(status: ["planned"]))
  end

  def test_no_match_gives_an_empty_list
    assert_empty Archsight::Requirements.collect(@db, of: 'ApplicationService: name == "Unrelated"')
    assert_empty Archsight::Requirements.collect(@db, of: 'ApplicationService: name == "Nope"')
  end

  def test_bad_query_raises
    assert_raises(Archsight::Query::QueryError) { Archsight::Requirements.collect(@db, of: "ApplicationService: (((") }
  end
end

# Open work plans its requirements instead of realizing them (planned, not implemented)
class WorkPackageRequirementsTest < Minitest::Test
  YAML_DOC = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Req:Shared
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Req:Done
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationWorkPackage
    metadata:
      name: Migration:One
    spec:
      plans:
        motivationRequirements: [Req:Shared]
      realizes:
        motivationRequirements: [Req:Done]
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationWorkPackage
    metadata:
      name: Migration:Two
    spec:
      plans:
        motivationRequirements: [Req:Shared]
  YAML

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "all.yaml"), YAML_DOC)
    @db = Archsight::Database.new(@dir)
    @db.reload!
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_planned_and_realized_requirements_of_work_packages
    entries = Archsight::Requirements.collect(@db, of: "ImplementationWorkPackage:")

    assert_equal "planned", entries.find { |e| e[:name] == "Req:Shared" }[:status]
    assert_equal "implemented", entries.find { |e| e[:name] == "Req:Done" }[:status]
  end

  def test_one_work_package_does_not_mix_in_the_requirements_of_another
    entries = Archsight::Requirements.collect(@db, of: 'ImplementationWorkPackage: name == "Migration:Two"')

    assert_equal(["Req:Shared"], entries.map { |e| e[:name] })
    assert_equal(["Migration:Two"], entries.first[:by].map { |b| b[:name] })
  end
end

# Components answer requirements themselves (not only through a service) and carry their own evidence
class ApplicationComponentRequirementsTest < Minitest::Test
  YAML_DOC = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Req:Encryption
      annotations:
        requirement/priority: must
    ---
    apiVersion: architecture/v1alpha1
    kind: ComplianceEvidence
    metadata:
      name: Evidence:TLS
      annotations:
        evidence/mechanism: |
          - TLS terminated at the gateway
    spec:
      satisfies:
        motivationRequirements: [Req:Encryption]
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Gateway
    spec:
      realizes:
        motivationRequirements: [Req:Encryption]
      evidencedBy:
        complianceEvidences: [Evidence:TLS]
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Worker
    spec:
      plans:
        motivationRequirements: [Req:Encryption]
  YAML

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "all.yaml"), YAML_DOC)
    @db = Archsight::Database.new(@dir)
    @db.reload!
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_components_realize_and_plan_requirements
    entry = Archsight::Requirements.collect(@db, of: "ApplicationComponent:").find { |e| e[:name] == "Req:Encryption" }

    assert_equal "implemented", entry[:status]
    by = entry[:by].map { |b| [b[:kind], b[:name], b[:status]] }

    assert_equal [%w[ApplicationComponent Gateway implemented], %w[ApplicationComponent Worker planned]], by
  end

  def test_a_component_is_evidenced_by_compliance_evidence
    gateway = @db.instance_by_kind("ApplicationComponent", "Gateway")
    evidence = @db.instance_by_kind("ComplianceEvidence", "Evidence:TLS")

    assert_equal [evidence], gateway.relations(:evidencedBy, :complianceEvidences)
    assert_equal [gateway], evidence.references_grouped.dig("ApplicationComponent", :evidencedBy)
  end
end
