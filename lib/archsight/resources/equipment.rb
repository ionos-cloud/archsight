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
    - Links between facilities (fibre routes, carrier circuits, `equipment/type: link`) and backbones made of them

    Model individual servers and VMs as `TechnologyNode`; use Equipment only when the physical grouping matters.

    ## How it connects

    - Equipment is `locatedAt` the facilities it stands in. A link between facilities is one Equipment that is
      `locatedAt` both end facilities
    - Equipment is `composedOf` other Equipment: a rack of its devices, a backbone of its links. The target must be
      Equipment too and the chain must not form a cycle
    - A technology service or node is `realizedBy` the Equipment it runs on or over (a network service by the link)
    - Equipment is optional: nodes and services can be `locatedAt` a facility directly
  MD

  icon "cpu"
  layer "physical"

  annotation "equipment/type",
             description: "Kind of equipment",
             title: "Equipment Type",
             enum: %w[rack network-fabric link cluster storage power cooling other],
             filter: :word,
             summary: true

  relation :locatedAt, :facilities, :Facility
  relation :composedOf, :equipment, :Equipment
end
