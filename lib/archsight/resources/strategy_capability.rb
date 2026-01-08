# frozen_string_literal: true

# StrategyCapability represents a strategic ability or function (ArchiMate Strategy Layer)
class Archsight::Resources::StrategyCapability < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents an ability that an organization possesses to achieve specific outcomes.

    ## ArchiMate Definition

    **Layer:** Strategy
    **Aspect:** Behavior

    A capability represents an ability that an active structure element, such as an
    organization, possesses. Capabilities are realized through a combination of people,
    processes, and technology working together.

    ## Usage

    Use StrategyCapability to represent:

    - Business capabilities (e.g., "Customer Provisioning")
    - Technical capabilities (e.g., "Automated Deployment")
    - Organizational abilities
    - Core competencies
    - Value-generating functions
  MD

  icon "strategy"
  layer "strategy"

  relation :realizes, :businessConstraints, :BusinessConstraint
  relation :realizes, :businessRequirements, :BusinessRequirement
  relation :servedBy, :businessActors, :BusinessActor
  relation :servedBy, :applicationServices, :ApplicationService
  relation :servedBy, :businessProcesses, :BusinessProcess
end
