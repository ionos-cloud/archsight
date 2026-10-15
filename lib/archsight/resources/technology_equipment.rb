# frozen_string_literal: true

# TechnologyEquipment represents racks, fabrics and physical clusters inside a facility
class Archsight::Resources::TechnologyEquipment < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents physical equipment inside a facility: racks, network fabrics, physical clusters.

    ## ArchiMate Definition

    **Layer:** Technology (physical element)
    **Aspect:** Active Structure

    TechnologyEquipment is one or more physical machines, tools or instruments that can create, use, store, move or transform
    materials.

    ## Usage

    Use TechnologyEquipment to represent:

    - Racks and rack rows
    - Network fabrics and switch stacks
    - Physical clusters (storage arrays, hardware pools) that technology nodes run on
    - Links between facilities (fibre routes, carrier circuits, `equipment/type: link`) and backbones made of them

    Model individual servers and VMs as `TechnologyNode`; use TechnologyEquipment only when the physical grouping matters.

    ## Not this kind

    - A machine that runs software (server, VM, appliance) is a `TechnologyNode`
    - The network that runs over the links is a `TechnologyCommunicationNetwork` `realizedBy` the equipment
    - A link is one element `locatedAt` its two facilities, not a `TechnologyService`

    Which kind to pick: "Choosing the Kind: Infrastructure" in the modeling guide.

    ## How it connects

    - TechnologyEquipment is `locatedAt` the facilities it stands in. A link between facilities is one TechnologyEquipment that is
      `locatedAt` both end facilities
    - TechnologyEquipment is `composedOf` other TechnologyEquipment: a rack of its devices, a backbone of its links. The target must be
      TechnologyEquipment too and the chain must not form a cycle
    - A technology service or node is `realizedBy` the TechnologyEquipment it runs on or over (a network service by the link)
    - TechnologyEquipment is optional: nodes and services can be `locatedAt` a facility directly
    - A `BusinessContract` `covers` the equipment it obliges the provider to deliver, and the `ImplementationWorkPackage` that
      installs or changes it `affects` it
  MD

  icon "cpu"
  layer "technology"

  annotation "equipment/type",
             description: "Kind of equipment",
             title: "TechnologyEquipment Type",
             enum: %w[rack network-fabric link cluster storage power cooling other],
             filter: :word,
             summary: true

  relation :locatedAt, :technologyFacilities, :TechnologyFacility
  relation :composedOf, :technologyEquipment, :TechnologyEquipment
end
