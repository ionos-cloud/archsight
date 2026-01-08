# frozen_string_literal: true

# MotivationStakeholder represents the role of an individual, team, or organization
# that represents their interests in the effects of the architecture (ArchiMate Motivation Layer)
class Archsight::Resources::MotivationStakeholder < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents the interest of an individual, team, or organization in the architecture.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Active Structure

    A stakeholder represents the role of an individual, team, or organization that
    represents their interests in the effects of the architecture. Stakeholders have
    concerns about capabilities, requirements, and constraints.

    ## Usage

    Use MotivationStakeholder to represent:

    - Product owners
    - Executive sponsors
    - Customer representatives
    - Regulatory bodies
    - Technical leadership
  MD

  icon "user-crown"
  layer "motivation"

  relation :hasConcern, :strategyCapabilities, :StrategyCapability
  relation :hasConcern, :businessRequirements, :BusinessRequirement
  relation :hasConcern, :businessConstraints, :BusinessConstraint
  relation :hasConcern, :goals, :MotivationGoal
end
