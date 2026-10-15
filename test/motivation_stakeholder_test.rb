# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class MotivationStakeholderTest < Minitest::Test
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: CustomerOrg
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessRole
    metadata:
      name: Role:DataProtectionOfficer
    spec:
      performedBy:
        businessActors: [CustomerOrg]
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Requirement:Encryption
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationStakeholder
    metadata:
      name: Stakeholder:Customer
    spec:
      hasConcern:
        motivationRequirements: [Requirement:Encryption]
      representedBy:
        businessActors: [CustomerOrg]
        businessRoles: [Role:DataProtectionOfficer]
  YAML

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def incoming(inst, verb) = (inst.references_grouped.dig("MotivationStakeholder", verb) || []).map(&:name)

  def test_the_source_of_a_requirement_reaches_the_actor
    with_db do |db|
      stakeholder = db.instance_by_kind("MotivationStakeholder", "Stakeholder:Customer")

      assert_equal ["CustomerOrg"], stakeholder.relations(:representedBy, :businessActors).map(&:name)
      assert_equal ["Role:DataProtectionOfficer"], stakeholder.relations(:representedBy, :businessRoles).map(&:name)
      assert_equal ["Stakeholder:Customer"], incoming(db.instance_by_kind("BusinessActor", "CustomerOrg"), :representedBy)
      assert_equal ["Stakeholder:Customer"], incoming(db.instance_by_kind("BusinessRole", "Role:DataProtectionOfficer"), :representedBy)
      assert_equal ["Stakeholder:Customer"], incoming(db.instance_by_kind("MotivationRequirement", "Requirement:Encryption"), :hasConcern)
      assert_empty Archsight::Linter.new(db).validate
    end
  end

  def test_a_stakeholder_is_represented_by_actors_and_roles_only
    yaml = RESOURCES.sub("    businessRoles: [Role:DataProtectionOfficer]", "    motivationRequirements: [Requirement:Encryption]")

    refute_equal RESOURCES, yaml
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  # representedBy points down, from the stakeholder (motivation) to the party (business). Nothing leads from an
  # actor or a role back to a stakeholder, so the relation can never close a cycle.
  def test_representedby_is_top_down_and_cannot_close_a_cycle
    edges = Archsight::Resources.resource_classes.to_h do |kind, klass|
      [kind, klass.declared_relations.map { |_verb, _key, target| target.to_s }.uniq]
    end
    reachable = lambda do |start|
      seen = Set.new
      queue = [start]
      while (kind = queue.shift)
        (edges[kind] || []).each do |target|
          next if seen.include?(target)

          seen << target
          queue << target
        end
      end
      seen
    end

    %w[BusinessActor BusinessRole].each do |party|
      refute_includes reachable.call(party), "MotivationStakeholder", "#{party} must not lead back to a stakeholder"
      refute(Archsight::Resources[party].declared_relations.any? { |verb, _key, _target| verb == :representedBy })
    end
  end
end
