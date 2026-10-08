# frozen_string_literal: true

# MotivationRequirement represents functional or non-functional requirements
class Archsight::Resources::MotivationRequirement < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a statement of need that must be realized by the architecture.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Passive Structure

    A requirement represents a statement of need defining a property that applies to a
    specific system. Requirements can be functional (what the system should do) or
    non-functional (how the system should behave).

    ## Usage

    Use MotivationRequirement to represent:

    - Compliance requirements (C5, ISO 27001)
    - Security requirements
    - Performance requirements
    - Functional specifications
    - Legal obligations (GDPR, NIS2)

    ## Who addresses it

    A requirement is where the process side and the application side meet:

    - **Process side:** a `BusinessControl` `satisfies` the requirement; a process is `guidedBy` the control
    - **Application side:** applications `realize` or `plan` the requirement and are `evidencedBy` `ComplianceEvidence`,
      which `satisfies` it

    Both show as incoming relations on the requirement's page.
  MD

  icon "task-list"
  layer "motivation"

  annotation "requirement/type",
             description: "Type of requirement (business or legal)",
             enum: %w[business legal compliance functional non-functional],
             summary: true

  annotation "requirement/reference",
             description: "Regulatory or standard reference (comma-separated for multiple)",
             filter: :list,
             enum: %w[c5-2020 itgs-2023 gdpr-2018 nis1 nis2 iso27001 sox pci-dss hipaa eu-data-act-2025 ens
                      iso27001-2022],
             summary: true

  annotation "requirement/priority",
             description: "Implementation priority (must, should, may)",
             filter: :word,
             enum: %w[must should may],
             summary: true

  annotation "requirement/story",
             description: "One-line business value statement explaining what the requirement enables",
             title: "Story",
             format: :markdown

  relation :realizes, :outcomes, :MotivationOutcome
end
