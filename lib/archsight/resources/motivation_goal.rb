# frozen_string_literal: true

# MotivationGoal represents a high-level statement of intent, direction, or desired end state
# for an organization and its stakeholders (ArchiMate Motivation Layer)
class Archsight::Resources::MotivationGoal < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a high-level statement of intent or desired end state for the organization.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Behavior

    A goal represents a high-level statement of intent, direction, or desired end state for
    an organization and its stakeholders. Goals are typically refined into more specific
    requirements that can be implemented.

    ## Usage

    Use MotivationGoal to represent:

    - Strategic objectives
    - Business targets
    - Quality goals
    - Compliance objectives
    - Performance targets
  MD

  icon "archery"
  layer "motivation"

  relation :realizes, :outcomes, :MotivationOutcome
  relation :refinedBy, :goals, :MotivationGoal
  relation :realizes, :businessRequirements, :BusinessRequirement
end
