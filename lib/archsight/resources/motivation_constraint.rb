# frozen_string_literal: true

# MotivationConstraint represents restrictions or limitations on architecture
class Archsight::Resources::MotivationConstraint < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents a factor that limits the realization of goals or influences architecture decisions.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Passive Structure

    A constraint represents a factor that prevents or obstructs the realization of goals.
    Constraints are typically imposed by external factors such as regulations, organizational
    policies, or technical limitations.

    ## Usage

    Use MotivationConstraint to represent:

    - Regulatory requirements (GDPR, SOX, PCI-DSS)
    - Security policies
    - Organizational standards
    - Technical limitations
    - Budget or resource constraints

    ## Security and risk modelling

    Use a constraint for rules that only restrict and are not a design statement: regulation, contractual duties,
    operational policy (the overlay paper has no element for operational policy). Policies stated as principles
    belong in `MotivationPrinciple`.
  MD

  icon "prohibition"
  layer "motivation"
end
