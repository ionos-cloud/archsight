# frozen_string_literal: true

# BusinessControl represents a control that guides a business process
class Archsight::Resources::BusinessControl < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents a control: a safeguard or decision step with an owner that guides how a business process is carried out.

    ## ArchiMate / TOGAF Definition

    **Layer:** Business
    **Aspect:** Behavior (guidance)

    ArchiMate has no control element. TOGAF's content metamodel has one: a decision-making step with
    accountability and authority, applied to a process or function. A control is therefore modelled as
    a business-layer kind that a `BusinessProcess` is guided by (`guidedBy`).

    ## Usage

    Use BusinessControl to represent:

    - Security and compliance controls (access review, network documentation, backup verification)
    - Operational checks that a process must pass (change approval, four-eyes principle)
    - Controls of a standard or framework (BSI C5, ISO 27001, SOC 2), linked to the requirements they satisfy

    ## How it connects

    - A `BusinessProcess` is `guidedBy` the control
    - The control is `ownedBy` the actor or role that is accountable for it and `executedBy` the actors or roles that carry it out
    - The control `satisfies` requirements and is `evidencedBy` compliance evidence

    A control addresses requirements from the **process side**. Whether an application implements a requirement is
    stated on the application (`realizes`, `plans`, `evidencedBy`), not on the control. Link evidence to a control
    only for the records the control itself produces (reviews, diagrams, change history, audit logs), and set the
    `evidence/type` of that evidence to `process`, `documentation` or `audit-log`.

    Put the best practices and the evidence requirements of a control in the description.

    ## Security and risk modelling

    A control is the process-side implementation of a control measure. `satisfies` the requirements (catalogue
    controls and control measures); a risk it reduces is `mitigatedBy` the control (written on the assessment).
    Group controls with `risk/domain` and `risk/category`.
  MD

  icon "shield-search"
  layer "business"

  annotation "control/id",
             description: "Identifier of the control in its catalogue (e.g. COS-07)",
             title: "Control ID",
             summary: true

  annotation "control/status",
             description: "Implementation status of the control",
             enum: %w[implemented partial planned not-implemented],
             filter: :word,
             summary: true

  annotation "control/frequency",
             description: "How often the control is carried out",
             enum: %w[continuous event-based daily weekly monthly quarterly semi-annually annually],
             filter: :word,
             summary: true

  annotation "control/objective",
             description: "What the control achieves, in one short paragraph",
             title: "Objective",
             format: :markdown

  annotation "control/last-review",
             description: "When the control was last reviewed (ISO 8601 date or time)",
             title: "Last review",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  annotation "control/next-review",
             description: "When the control is due for review (ISO 8601 date or time)",
             title: "Next review",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  relation :ownedBy, :businessActors, :BusinessActor
  relation :executedBy, :businessActors, :BusinessActor
  relation :ownedBy, :businessRoles, :BusinessRole
  relation :executedBy, :businessRoles, :BusinessRole
  relation :satisfies, :motivationRequirements, :MotivationRequirement
  relation :evidencedBy, :complianceEvidences, :ComplianceEvidence
end
