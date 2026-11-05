# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class RequirementRefinementTest < Minitest::Test
  YAML_DOC = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Req:ITGS:CON.3.A1
      annotations:
        requirement/type: compliance
        requirement/reference: itgs-2023
    spec:
      refinedBy:
        motivationRequirements: [Req:Backup:Daily]
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Req:Backup:Daily
    spec:
      realizes:
        outcomes: [Outcome:Resilience]
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationOutcome
    metadata:
      name: Outcome:Resilience
    spec: {}
  YAML

  def test_a_requirement_is_refined_by_requirements_and_they_show_it_as_incoming
    with_db do |db|
      catalogue = db.instance_by_kind("MotivationRequirement", "Req:ITGS:CON.3.A1")
      derived = db.instance_by_kind("MotivationRequirement", "Req:Backup:Daily")

      assert_equal ["Req:Backup:Daily"], catalogue.relations(:refinedBy, :motivationRequirements).map(&:name)
      assert_equal ["Req:ITGS:CON.3.A1"], (derived.references_grouped.dig("MotivationRequirement", :refinedBy) || []).map(&:name)
    end
  end

  def test_the_example_lints_clean
    with_db { |db| assert_empty Archsight::Linter.new(db).validate }
  end

  def test_only_requirements_can_refine_a_requirement
    yaml = YAML_DOC.sub("refinedBy:\n    motivationRequirements: [Req:Backup:Daily]", "refinedBy:\n    outcomes: [Outcome:Resilience]")

    refute_equal YAML_DOC, yaml
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  private

  def with_db(yaml = YAML_DOC)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end
end
