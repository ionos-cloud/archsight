# frozen_string_literal: true

# ImplementationWorkPackage represents a series of actions that achieves a result within a time frame
class Archsight::Resources::ImplementationWorkPackage < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents a series of actions identified and designed to achieve specific results within specified time and resource constraints.

    ## ArchiMate Definition

    **Layer:** Implementation & Migration
    **Aspect:** Behavior

    A work package is a piece of work with a defined start and end that produces deliverables. It is how the
    architecture changes: projects, measures, remediation of findings, roadmap items.

    ## Usage

    Use ImplementationWorkPackage to represent:

    - Projects and roadmap items that move the architecture from one plateau to the next
    - Measures and realisation plans of an ISMS (due date, status, owner)
    - Remediation of a risk, vulnerability or audit finding (the `MotivationAssessment` is `mitigatedBy` the work package)
    - Audit programmes and recurring reviews

    ## How it connects

    - `ownedBy` the accountable actor or role, `performedBy` the actors or roles that carry it out
    - `realizes` deliverables (its results), requirements and goals
    - `affects` the assets it changes; the assessments (risks, findings) it treats are `mitigatedBy` it (written on the assessment)
    - `triggers` the work packages that follow it; an `ImplementationEvent` can trigger it
    - A `ImplementationGap` is `closedBy` it

    ## Security and risk modelling

    Set `workpackage/type` `remediation` and list the work package under `mitigatedBy` of the risk or finding to see what is open; filter
    by `workpackage/status`, `workpackage/due` and `risk/domain` for the plan of one domain.
  MD

  icon "hammer"
  layer "implementation"

  annotation "workpackage/type",
             description: "What kind of work this is (specialization of the work package)",
             enum: %w[project measure remediation audit-programme change],
             filter: :word,
             summary: true
  annotation "workpackage/status",
             description: "Where the work is",
             enum: %w[planned in-progress done cancelled],
             filter: :word,
             summary: true
  annotation "workpackage/priority",
             description: "How urgent the work is",
             enum: %w[low medium high critical],
             filter: :word
  annotation "workpackage/start",
             description: "When the work starts (ISO 8601 date or time)",
             title: "Start",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }
  annotation "workpackage/due",
             description: "When the work is due (ISO 8601 date or time)",
             title: "Due",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }
  annotation "workpackage/completed",
             description: "When the work was completed (ISO 8601 date or time)",
             title: "Completed",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  relation :ownedBy, :businessActors, :BusinessActor
  relation :performedBy, :businessActors, :BusinessActor
  relation :ownedBy, :businessRoles, :BusinessRole
  relation :performedBy, :businessRoles, :BusinessRole
  relation :realizes, :implementationDeliverables, :ImplementationDeliverable
  relation :realizes, :motivationRequirements, :MotivationRequirement
  relation :realizes, :goals, :MotivationGoal
  relation :affects, :businessProcesses, :BusinessProcess
  relation :affects, :applicationComponents, :ApplicationComponent
  relation :affects, :applicationServices, :ApplicationService
  relation :affects, :technologyNodes, :TechnologyNode
  relation :triggers, :implementationWorkPackages, :ImplementationWorkPackage
end
