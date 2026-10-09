# frozen_string_literal: true

# MotivationAssessment represents the outcome of an analysis: a risk, a vulnerability, a finding
class Archsight::Resources::MotivationAssessment < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents the outcome of an analysis of some aspect of the architecture with respect to a driver: a risk, a
    vulnerability, an audit finding, a supplier or protection-need assessment.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Behavior

    An assessment is the outcome of an analysis of the state of affairs of the enterprise with respect to some
    driver. In the risk and security overlay of the Open Group paper (*Modeling Enterprise Risk Management and
    Security with the ArchiMate Language*) a **risk** is a quantification of a threat and a **vulnerability** is
    the result of analysing weaknesses of architecture elements; both are assessments with a type. Set
    `assessment/type` to say which.

    ## Usage

    Use MotivationAssessment to represent:

    - Risks (`risk`) with an initial and a residual profile and a treatment decision
    - Vulnerabilities (`vulnerability`), also the results of a scan or penetration test
    - Audit and review findings (`finding`)
    - Supplier assessments (`supplier`) and protection-need analyses (`protection-need`)

    ## Risk profile

    Initial risk is the risk before mitigation, residual risk the one after. Describe both with likelihood and
    impact (`risk/initial-*`, `risk/residual-*`) and record the decision in `risk/treatment` (avoid, transfer,
    mitigate, accept).

    ## How it connects

    - A `MotivationDriver` (the threat) `influences` the risk
    - The assessment `assesses` the assets it is about (applications, nodes, processes, data, suppliers)
    - A vulnerability `influences` the loss events it makes possible; a risk `influences` other risks
    - A `MotivationGoal` (control objective), a `MotivationRequirement` (control measure) or a `BusinessControl`
      `mitigates` it
    - It is `ownedBy` the accountable actor
  MD

  icon "clipboard-check"
  layer "motivation"

  likelihood = %w[very-low low medium high very-high]

  annotation "assessment/id",
             description: "Identifier of the assessment in its register (risk id, CVE, finding number)",
             title: "Assessment ID"

  annotation "assessment/type",
             description: "What kind of assessment this is (specialization of the assessment)",
             enum: %w[risk vulnerability finding supplier protection-need],
             filter: :word,
             summary: true

  annotation "assessment/status",
             description: "Where the assessment is in its life cycle",
             enum: %w[open treating accepted closed],
             filter: :word,
             summary: true

  annotation "assessment/severity",
             description: "Severity of a vulnerability or finding",
             enum: %w[info low medium high critical],
             filter: :word

  annotation "assessment/assessed",
             description: "When the assessment was made (ISO 8601 date or time)",
             title: "Assessed",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  annotation "risk/initial-likelihood",
             description: "Likelihood of the loss before mitigation",
             enum: likelihood,
             filter: :word

  annotation "risk/initial-impact",
             description: "Impact of the loss before mitigation",
             enum: likelihood,
             filter: :word

  annotation "risk/residual-likelihood",
             description: "Likelihood of the loss after mitigation",
             enum: likelihood,
             filter: :word

  annotation "risk/residual-impact",
             description: "Impact of the loss after mitigation",
             enum: likelihood,
             filter: :word

  annotation "risk/treatment",
             description: "How the risk is treated",
             enum: %w[avoid transfer mitigate accept],
             filter: :word,
             summary: true

  relation :ownedBy, :businessActors, :BusinessActor
  relation :assesses, :businessProcesses, :BusinessProcess
  relation :assesses, :businessActors, :BusinessActor
  relation :assesses, :applicationComponents, :ApplicationComponent
  relation :assesses, :applicationServices, :ApplicationService
  relation :assesses, :technologyNodes, :TechnologyNode
  relation :assesses, :dataObjects, :DataObject
  relation :influences, :businessEvents, :BusinessEvent
  relation :influences, :applicationEvents, :ApplicationEvent
  relation :influences, :technologyEvents, :TechnologyEvent
  relation :influences, :motivationAssessments, :MotivationAssessment
end
