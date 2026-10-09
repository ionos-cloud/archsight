# frozen_string_literal: true

# ImplementationDeliverable represents a precisely defined result of a work package
class Archsight::Resources::ImplementationDeliverable < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents a precisely defined result of a work package.

    ## ArchiMate Definition

    **Layer:** Implementation & Migration
    **Aspect:** Passive Structure

    A deliverable is a tangible or intangible result that a work package produces: a document, a system, a changed
    process. It realizes requirements, goals and plateaus.

    ## Usage

    Use ImplementationDeliverable to represent:

    - Documents and reports produced by a project or an audit
    - Systems and process changes that go live
    - The artefact that becomes compliance evidence once it exists

    ## How it connects

    - A `ImplementationWorkPackage` `realizes` it
    - It is `ownedBy` an actor and `realizes` plateaus, requirements, goals, outcomes and `ComplianceEvidence`

    ## Security and risk modelling

    A deliverable of type `evidence` that `realizes` a `ComplianceEvidence` ties the plan (work package) to the proof
    (evidence) of a control measure.
  MD

  icon "package"
  layer "implementation"

  annotation "deliverable/type",
             description: "What kind of result this is (specialization of the deliverable)",
             enum: %w[document system process-change report evidence],
             filter: :word,
             summary: true
  annotation "deliverable/status",
             description: "Where the result is",
             enum: %w[planned in-progress delivered accepted],
             filter: :word,
             summary: true
  annotation "deliverable/due",
             description: "When the result is due (ISO 8601 date or time)",
             title: "Due",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  relation :ownedBy, :businessActors, :BusinessActor
  relation :ownedBy, :businessRoles, :BusinessRole
  relation :realizes, :implementationPlateaus, :ImplementationPlateau
  relation :realizes, :motivationRequirements, :MotivationRequirement
  relation :realizes, :goals, :MotivationGoal
  relation :realizes, :outcomes, :MotivationOutcome
  relation :realizes, :complianceEvidences, :ComplianceEvidence
end
