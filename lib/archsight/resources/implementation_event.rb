# frozen_string_literal: true

# ImplementationEvent represents a state change related to implementation or migration
class Archsight::Resources::ImplementationEvent < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents a state change related to implementation or migration.

    ## ArchiMate Definition

    **Layer:** Implementation & Migration
    **Aspect:** Behavior

    An implementation event is something that happens during implementation or migration and may trigger work: a
    milestone reached, a go-live, a decommissioning, a review date or a deadline.

    ## Usage

    Use ImplementationEvent to represent:

    - Milestones and go-lives of a roadmap
    - Deadlines (certification audit, end of a transition period)
    - Reviews and decommissioning dates

    ## How it connects

    - `ownedBy` an actor
    - `triggers` work packages and plateaus

    Events of the running architecture (threat and loss events, incidents) are `BusinessEvent`, `ApplicationEvent`
    and `TechnologyEvent`.
  MD

  icon "calendar-check"
  layer "implementation"

  annotation "event/type",
             description: "What kind of event this is (specialization of the implementation event)",
             enum: %w[milestone go-live decommission review deadline],
             filter: :word,
             summary: true
  annotation "event/occurred",
             description: "When the event happens or happened (ISO 8601 date or time)",
             title: "Occurred",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  relation :ownedBy, :businessActors, :BusinessActor
  relation :triggers, :implementationWorkPackages, :ImplementationWorkPackage
  relation :triggers, :implementationPlateaus, :ImplementationPlateau
end
