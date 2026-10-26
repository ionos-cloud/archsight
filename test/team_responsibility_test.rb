# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TeamResponsibilityTest < Minitest::Test
  # A service chain whose build team (Dev) differs from its run team (Ops, a role for the component)
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Dev
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Ops
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessRole
    metadata:
      name: Role:OnCall
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Comp
    spec:
      maintainedBy:
        businessActors: [Team:Dev]
      operatedBy:
        businessRoles: [Role:OnCall]
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: AppSvc
    spec:
      maintainedBy:
        businessActors: [Team:Dev]
      operatedBy:
        businessActors: [Team:Ops]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: TechSvc
    spec:
      maintainedBy:
        businessActors: [Team:Dev]
      operatedBy:
        businessActors: [Team:Ops]
  YAML

  KINDS = %w[ApplicationComponent ApplicationService TechnologyService].freeze

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def incoming(inst, kind, verb) = (inst.references_grouped.dig(kind, verb) || []).map(&:name).sort

  def targets(kind, verb)
    Archsight::Resources.const_get(kind).declared_relations.select { |v, _, _| v == verb }.map { |_, _, target| target.to_s }.sort
  end

  def test_the_kinds_declare_build_and_run_responsibility
    KINDS.each do |kind|
      assert_equal %w[BusinessActor], targets(kind, :maintainedBy), kind
      assert_equal %w[BusinessActor BusinessRole], targets(kind, :operatedBy), kind
    end
  end

  def test_the_teams_list_what_they_build_and_run
    with_db do |db|
      dev = db.instance_by_kind("BusinessActor", "Team:Dev")
      ops = db.instance_by_kind("BusinessActor", "Team:Ops")
      role = db.instance_by_kind("BusinessRole", "Role:OnCall")

      assert_equal %w[AppSvc Comp TechSvc], KINDS.flat_map { |k| incoming(dev, k, :maintainedBy) }.sort
      assert_equal %w[AppSvc TechSvc], KINDS.flat_map { |k| incoming(ops, k, :operatedBy) }.sort
      assert_equal %w[Comp], incoming(role, "ApplicationComponent", :operatedBy)
    end
  end
end
