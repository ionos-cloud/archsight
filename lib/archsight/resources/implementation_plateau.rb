# frozen_string_literal: true

# ImplementationPlateau represents a relatively stable state of the architecture
class Archsight::Resources::ImplementationPlateau < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents a relatively stable state of the architecture that exists during a limited period of time.

    ## ArchiMate Definition

    **Layer:** Implementation & Migration
    **Aspect:** Composite

    A plateau is a coherent set of architecture elements as they exist (or will exist) in one period. Plateaus
    are the points of a migration path: baseline, transition states, target.

    ## Usage

    Use ImplementationPlateau to represent:

    - The baseline (today's architecture) and the target architecture
    - Transition architectures of a roadmap
    - The state of the ISMS scope at a certification date

    ## How it connects

    - A plateau `contains` the components, services, nodes, processes and requirements that belong to it
    - It `triggers` the next plateau (migration path)
    - A `ImplementationDeliverable` `realizes` it; a `ImplementationGap` `compares` two plateaus
  MD

  icon "packages"
  layer "implementation"

  annotation "plateau/type",
             description: "Position on the migration path",
             enum: %w[baseline transition target],
             filter: :word,
             summary: true
  annotation "plateau/status",
             description: "Where the plateau is",
             enum: %w[planned current past],
             filter: :word,
             summary: true
  annotation "plateau/from",
             description: "When the plateau starts (ISO 8601 date or time)",
             title: "From",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }
  annotation "plateau/until",
             description: "When the plateau ends (ISO 8601 date or time)",
             title: "Until",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  relation :contains, :applicationComponents, :ApplicationComponent
  relation :contains, :applicationServices, :ApplicationService
  relation :contains, :technologyNodes, :TechnologyNode
  relation :contains, :businessProcesses, :BusinessProcess
  relation :contains, :motivationRequirements, :MotivationRequirement
  relation :triggers, :implementationPlateaus, :ImplementationPlateau
end
