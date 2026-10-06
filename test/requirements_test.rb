# frozen_string_literal: true

require_relative "test_helper"

class RequirementsTest < Minitest::Test
  YAML_DOC = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: BusinessRequirement
    metadata:
      name: Req:A
      annotations:
        requirement/priority: must
        requirement/story: Story **A**
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessRequirement
    metadata:
      name: Req:B
      annotations:
        requirement/priority: should
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessRequirement
    metadata:
      name: Req:C
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessRequirement
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
        businessRequirements: [Req:A]
      partiallyRealizes:
        businessRequirements: [Req:B]
      plans:
        businessRequirements: [Req:C, Req:Must0]
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Restore
    spec:
      plans:
        businessRequirements: [Req:A, Req:B]
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
