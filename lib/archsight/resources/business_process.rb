# frozen_string_literal: true

# BusinessProcess represents a structured business workflow or procedure
class Archsight::Resources::BusinessProcess < Archsight::Resources::Base
  include_annotations :git, :architecture, :asset, :risk

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

    ## Security and risk modelling

    A process is an asset at risk (set `asset/value` and the protection needs `asset/confidentiality`,
    `asset/integrity`, `asset/availability`), is `guidedBy` the controls that protect it, is hit by loss
    events and is triggered by events. Group it with `risk/domain`.
  MD

  icon "kanban-board"
  layer "business"

  relation :realizes, :motivationConstraints, :MotivationConstraint
  relation :realizes, :motivationRequirements, :MotivationRequirement
  relation :servedBy, :applicationServices, :ApplicationService
  relation :performedBy, :businessActors, :BusinessActor
  relation :guidedBy, :businessControls, :BusinessControl
end
