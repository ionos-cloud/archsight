# frozen_string_literal: true

# BusinessRequirement represents functional or non-functional requirements
class Archsight::Resources::BusinessRequirement < Archsight::Resources::Base
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

    Use BusinessRequirement to represent:

    - Compliance requirements (C5, ISO 27001)
    - Security requirements
    - Performance requirements
    - Functional specifications
    - Legal obligations (GDPR, NIS2)
  MD

  icon "task-list"
  layer "business"

  annotation "requirement/type",
             description: "Type of requirement (business or legal)",
             enum: %w[business legal compliance functional non-functional]

  annotation "requirement/reference",
             description: "Regulatory or standard reference (comma-separated for multiple)",
             filter: :list,
             enum: %w[c5-2020 itgs-2023 gdpr-2018 nis1 nis2 iso27001 sox pci-dss hipaa eu-data-act-2025 ens
                      iso27001-2022],
             list: true

  annotation "requirement/priority",
             description: "Implementation priority (must, should, may)",
             filter: :word,
             enum: %w[must should may],
             list: true

  annotation "requirement/story",
             description: "One-line business value statement explaining what the requirement enables",
             title: "Story",
             format: :markdown

  relation :realizes, :outcomes, :MotivationOutcome
end
