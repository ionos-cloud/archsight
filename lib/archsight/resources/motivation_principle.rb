# frozen_string_literal: true

# MotivationPrinciple represents a normative property of all systems in a context, such as a policy
class Archsight::Resources::MotivationPrinciple < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents a statement of intent that defines a general property that applies to any system in a context: a
    principle, and at design level a policy.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Passive Structure

    A principle is a qualitative statement of intent that should be met by the architecture. In the risk and
    security overlay of the Open Group paper (*Modeling Enterprise Risk Management and Security with the ArchiMate
    Language*) a policy maps to a principle; risk policy and security policy are specializations. Set
    `principle/type` to say which.

    ## Usage

    Use MotivationPrinciple to represent:

    - Security and risk policies (information security policy, access control policy)
    - Guidelines and procedures that state how a rule is applied
    - Architecture principles

    Rules that only restrict (regulation, an operational policy that is not a design statement) stay
    `MotivationConstraint`. The text of a policy belongs in a `Page`; link it with `[[Page]]` in the description.

    ## How it connects

    - A principle is `ownedBy` the actor or role that issued it
    - A `MotivationRequirement` (control measure) `realizes` the principle
  MD

  icon "book"
  layer "motivation"

  annotation "principle/type",
             description: "What kind of statement this is (specialization of the principle)",
             enum: %w[principle policy security-policy risk-policy guideline procedure],
             filter: :word,
             summary: true

  annotation "principle/status",
             description: "Whether the statement is in force",
             enum: %w[draft valid retired],
             filter: :word,
             summary: true

  annotation "principle/classification",
             description: "Confidentiality classification of the statement",
             enum: %w[public internal confidential strictly-confidential],
             filter: :word

  annotation "principle/valid-from",
             description: "When the statement comes into force (ISO 8601 date or time)",
             title: "Valid from",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  annotation "principle/valid-until",
             description: "When the statement has to be reviewed or ends (ISO 8601 date or time)",
             title: "Valid until",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  annotation "principle/framework",
             description: "Standards the statement maps to (comma-separated, e.g. c5-2020, iso27001-2022)",
             title: "Framework mapping",
             filter: :list

  relation :ownedBy, :businessActors, :BusinessActor
  relation :ownedBy, :businessRoles, :BusinessRole
end
