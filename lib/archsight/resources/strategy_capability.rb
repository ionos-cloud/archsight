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

    ## Choosing this kind

    **Question:** What must the organization be *able* to do?
    **Test:** It survives swapping product, team and technology. It is not a certificate or a quality.
    **Name:** An ability noun phrase ("Payment Processing"), never a product, team or technology.

    A product `realizes` the capability. Only internal capabilities that no product carries are `servedBy` a service.
    See the modeling guide, "Choosing the Kind".
  MD

  icon "strategy"
  layer "strategy"

  relation :realizes, :motivationConstraints, :MotivationConstraint
  relation :realizes, :motivationRequirements, :MotivationRequirement
  relation :servedBy, :businessActors, :BusinessActor
  relation :servedBy, :applicationServices, :ApplicationService
  relation :servedBy, :businessProcesses, :BusinessProcess
end
