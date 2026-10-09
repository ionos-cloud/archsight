# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The risk and security overlay (Open Group paper): threat -> risk -> control objective -> control measure -> control
class SecurityModelingTest < Minitest::Test
  CHAIN = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Security
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyNode
    metadata:
      name: Node:Web1
      annotations:
        asset/availability: high
        risk/domain: customer-data
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationDriver
    metadata:
      name: Threat:Intrusion
      annotations:
        driver/type: threat
    spec:
      influences:
        motivationAssessments:
          - Risk:Intrusion
      triggers:
        businessEvents:
          - Loss:DataLeak
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationAssessment
    metadata:
      name: Risk:Intrusion
      annotations:
        assessment/type: risk
        risk/initial-likelihood: high
        risk/residual-likelihood: low
        risk/treatment: mitigate
        risk/domain: customer-data
    spec:
      ownedBy:
        businessActors:
          - Team:Security
      assesses:
        technologyNodes:
          - Node:Web1
      mitigatedBy:
        goals:
          - Objective:ReduceExposure
        businessControls:
          - Control:FirewallReview
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationAssessment
    metadata:
      name: Vulnerability:OpenPort
      annotations:
        assessment/type: vulnerability
        assessment/severity: high
    spec:
      assesses:
        technologyNodes:
          - Node:Web1
      influences:
        businessEvents:
          - Loss:DataLeak
        motivationAssessments:
          - Risk:Intrusion
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessEvent
    metadata:
      name: Loss:DataLeak
      annotations:
        event/type: loss-event
        event/occurred: '2026-09-01'
    spec:
      causedBy:
        technologyNodes:
          - Node:Web1
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyEvent
    metadata:
      name: Attack:PortScan
      annotations:
        event/type: attack
    spec:
      triggers:
        businessEvents:
          - Loss:DataLeak
      affects:
        technologyNodes:
          - Node:Web1
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationEvent
    metadata:
      name: Alert:LoginBurst
      annotations:
        event/type: threat-event
    spec:
      triggers:
        businessEvents:
          - Loss:DataLeak
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationGoal
    metadata:
      name: Objective:ReduceExposure
      annotations:
        goal/type: control-objective
    spec:
      realizes:
        motivationRequirements:
          - Measure:Firewall
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationPrinciple
    metadata:
      name: Policy:AccessControl
      annotations:
        principle/type: security-policy
        principle/status: valid
        principle/valid-from: '2026-01-01'
    spec:
      ownedBy:
        businessActors:
          - Team:Security
    ---
    apiVersion: architecture/v1alpha1
    kind: MotivationRequirement
    metadata:
      name: Measure:Firewall
      annotations:
        requirement/type: control-measure
    spec:
      realizes:
        motivationPrinciples:
          - Policy:AccessControl
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessControl
    metadata:
      name: Control:FirewallReview
    spec:
      satisfies:
        motivationRequirements:
          - Measure:Firewall
  YAML

  def with_db(yaml = CHAIN)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false)
      db.reload!
      yield db
    end
  end

  def changed(from, to)
    assert_includes CHAIN, from
    CHAIN.sub(from, to)
  end

  def test_new_kinds_sit_on_their_layers
    { "BusinessEvent" => "business", "ApplicationEvent" => "application", "TechnologyEvent" => "technology",
      "MotivationAssessment" => "motivation", "MotivationDriver" => "motivation",
      "MotivationPrinciple" => "motivation" }.each do |kind, layer|
      assert_equal layer, Archsight::Resources[kind].layer, kind
    end
  end

  def test_the_whole_chain_loads_and_links_both_ways
    with_db do |db|
      risk = db.instance_by_kind("MotivationAssessment", "Risk:Intrusion")
      threat = db.instance_by_kind("MotivationDriver", "Threat:Intrusion")
      goal = db.instance_by_kind("MotivationGoal", "Objective:ReduceExposure")
      measure = db.instance_by_kind("MotivationRequirement", "Measure:Firewall")
      control = db.instance_by_kind("BusinessControl", "Control:FirewallReview")

      assert_equal [risk], threat.relations(:influences, :motivationAssessments)
      assert_equal [goal], risk.relations(:mitigatedBy, :goals)
      assert_equal [control], risk.relations(:mitigatedBy, :businessControls)
      assert_equal [measure], goal.relations(:realizes, :motivationRequirements)
      assert_equal [measure], control.relations(:satisfies, :motivationRequirements)
      assert_equal [risk], goal.references_grouped.dig("MotivationAssessment", :mitigatedBy)
    end
  end

  def test_events_trigger_across_layers_and_are_listed_on_the_loss_event
    with_db do |db|
      loss = db.instance_by_kind("BusinessEvent", "Loss:DataLeak")

      assert_equal "loss-event", loss.annotations["event/type"]
      assert_equal %w[ApplicationEvent MotivationAssessment MotivationDriver TechnologyEvent],
                   loss.references_grouped.keys.sort
    end
  end

  def test_a_vulnerability_is_found_on_the_node_it_assesses
    with_db do |db|
      node = db.instance_by_kind("TechnologyNode", "Node:Web1")
      assessed = node.references_grouped.dig("MotivationAssessment", :assesses).map(&:name)

      assert_equal %w[Risk:Intrusion Vulnerability:OpenPort], assessed.sort
    end
  end

  def annotation(kind, key)
    Archsight::Resources[kind].annotations.find { |a| a.key == key }
  end

  def test_event_type_is_checked
    assert annotation("BusinessEvent", "event/type").valid?("loss-event")
    assert annotation("TechnologyEvent", "event/type").valid?("attack")
    refute annotation("ApplicationEvent", "event/type").valid?("nonsense")
  end

  def test_assessment_type_and_treatment_are_checked
    assert annotation("MotivationAssessment", "assessment/type").valid?("vulnerability")
    refute annotation("MotivationAssessment", "assessment/type").valid?("guess")
    assert annotation("MotivationAssessment", "risk/treatment").valid?("accept")
    refute annotation("MotivationAssessment", "risk/treatment").valid?("ignore")
  end

  def test_dates_must_be_iso_dates
    assert annotation("BusinessEvent", "event/occurred").valid?("2026-09-01")
    refute annotation("BusinessEvent", "event/occurred").valid?("yesterday")
    refute annotation("MotivationPrinciple", "principle/valid-from").valid?("soon")
  end

  def test_a_threat_cannot_trigger_a_process
    yaml = changed("  triggers:\n    businessEvents:\n      - Loss:DataLeak\n---\napiVersion: architecture/v1alpha1\n" \
                   "kind: MotivationAssessment\nmetadata:\n  name: Risk:Intrusion",
                   "  triggers:\n    businessProcesses:\n      - Loss:DataLeak\n---\napiVersion: architecture/v1alpha1\n" \
                   "kind: MotivationAssessment\nmetadata:\n  name: Risk:Intrusion")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_a_requirement_cannot_realize_a_goal
    yaml = changed("spec:\n  realizes:\n    motivationPrinciples:",
                   "spec:\n  realizes:\n    goals:\n      - Objective:ReduceExposure\n    motivationPrinciples:")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_a_principle_cannot_realize_a_goal
    yaml = changed("      - Team:Security\n---\napiVersion: architecture/v1alpha1\nkind: MotivationRequirement",
                   "      - Team:Security\n  realizes:\n    goals:\n      - Objective:ReduceExposure\n---\napiVersion: architecture/v1alpha1\nkind: MotivationRequirement")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_control_measure_is_a_requirement_type_and_evidence_may_be_not_applicable
    assert_includes Archsight::Resources::MotivationRequirement.annotation_enum("requirement/type"), "control-measure"
    assert_includes Archsight::Resources::ComplianceEvidence.annotation_enum("evidence/status"), "not-applicable"
  end

  def test_asset_and_risk_annotations_group_resources
    node = Archsight::Resources::TechnologyNode

    assert_includes node.filterable_annotations.map(&:key), "risk/domain"
    assert_includes node.annotations.map(&:key), "asset/confidentiality"
  end
end
