# frozen_string_literal: true

# BusinessConstraint represents restrictions or limitations on architecture
class Archsight::Resources::BusinessConstraint < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a factor that limits the realization of goals or influences architecture decisions.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Passive Structure

    A constraint represents a factor that prevents or obstructs the realization of goals.
    Constraints are typically imposed by external factors such as regulations, organizational
    policies, or technical limitations.

    ## Usage

    Use BusinessConstraint to represent:

    - Regulatory requirements (GDPR, SOX, PCI-DSS)
    - Security policies
    - Organizational standards
    - Technical limitations
    - Budget or resource constraints
  MD

  icon "prohibition"
  layer "business"
end
