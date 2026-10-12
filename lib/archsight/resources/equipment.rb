# frozen_string_literal: true

# Equipment represents racks, fabrics and physical clusters inside a facility
class Archsight::Resources::Equipment < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents physical equipment inside a facility: racks, network fabrics, physical clusters.

    ## ArchiMate Definition

    **Layer:** Physical
    **Aspect:** Active Structure

    Equipment is one or more physical machines, tools or instruments that can create, use, store, move or transform
    materials.

    ## Usage

    Use Equipment to represent:

    - Racks and rack rows
    - Network fabrics and switch stacks
    - Physical clusters (storage arrays, hardware pools) that technology nodes run on

    Model individual servers and VMs as `TechnologyNode`; use Equipment only when the physical grouping matters.

    ## How it connects

    - Equipment is `locatedAt` the facilities it stands in
    - Equipment is optional: nodes and services can be `locatedAt` a facility directly
  MD

  icon "cpu"
  layer "physical"

  annotation "equipment/type",
             description: "Kind of equipment",
             title: "Equipment Type",
             enum: %w[rack network-fabric cluster storage power cooling other],
             filter: :word,
             summary: true

  relation :locatedAt, :facilities, :Facility
end
