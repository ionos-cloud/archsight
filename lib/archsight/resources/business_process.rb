# frozen_string_literal: true

# BusinessProcess represents a structured business workflow or procedure
class Archsight::Resources::BusinessProcess < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a sequence of business behaviors that achieves a specific outcome.

    ## ArchiMate Definition

    **Layer:** Business
    **Aspect:** Behavior

    A business process represents a sequence of business behaviors that achieves a specific
    outcome such as a defined set of products or business services. It orchestrates the
    activities performed by business actors using application services.

    ## Usage

    Use BusinessProcess to represent:

    - Customer onboarding workflows
    - Incident response procedures
    - Change management processes
    - Release deployment pipelines
    - Support escalation processes
  MD

  icon "kanban-board"
  layer "business"

  relation :realizes, :businessConstraints, :BusinessConstraint
  relation :realizes, :businessRequirements, :BusinessRequirement
  relation :servedBy, :applicationServices, :ApplicationService
  relation :performedBy, :businessActors, :BusinessActor
end
