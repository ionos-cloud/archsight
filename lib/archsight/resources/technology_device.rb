# frozen_string_literal: true

# TechnologyDevice represents one physical machine: a server, switch, router, firewall or appliance
class Archsight::Resources::TechnologyDevice < Archsight::Resources::Base
  include_annotations :git, :architecture, :asset, :risk

  description <<~MD
    Represents one physical machine: a server, a switch, a router, a firewall, a terminal server or an appliance.

    ## ArchiMate Definition

    **Layer:** Technology
    **Aspect:** Active Structure

    A device is a physical IT resource upon which system software and artifacts may be stored or deployed for
    execution. It is a specialization of a node.

    ## Usage

    Use TechnologyDevice when the individual machine matters: which room it stands in, which switch it is cabled to,
    which machines a failure domain loses.

    - One element per physical machine (name it after the host: "Device:Frankfurt:Server01")
    - A group of machines with one role ("the hypervisors of the platform") stays a logical `TechnologyNode` that is
      `realizedBy` its devices
    - A virtual chassis, a stack or a cluster pair is a device `composedOf` its member devices

    ## Not this kind

    - A VM, a Kubernetes node or a host role is a `TechnologyNode`
    - A rack, a fabric or a link between sites is `TechnologyEquipment` (a rack is `composedOf` its devices)
    - The network a switch builds is a `TechnologyCommunicationNetwork` `realizedBy` the switch

    Which kind to pick: "Choosing the Kind: Infrastructure" in the modeling guide.

    ## How it connects

    - A device is `locatedAt` the `TechnologyFacility` it stands in, usually a room (`facility/type: room`)
    - A device is `connectedTo` the devices it is cabled to (ArchiMate association). The cable is declared once, on
      one of the two devices; the other shows it as incoming. Cabling is cyclic by nature and stays out of the
      cycle check
    - A device is `composedOf` its members (virtual chassis, stack)
    - A `TechnologyNode` is `realizedBy` the devices it consists of
    - A `TechnologyCommunicationNetwork` is `realizedBy` its switches and routers and `connects` the devices attached
      to it
    - `TechnologyEquipment` (a rack, a delivered hardware block) is `composedOf` its devices

    A device points to nothing above it: nodes, networks and equipment point down to the device, so the relations
    stay free of cycles.
  MD

  icon "server"
  layer "technology"

  annotation "device/type",
             description: "Kind of device",
             title: "Device Type",
             enum: %w[server switch router firewall terminal-server appliance other],
             filter: :word,
             summary: true
  annotation "device/role",
             description: "What the device does, e.g. hypervisor, storage, leaf, spine, core, management",
             title: "Role",
             filter: :word,
             summary: true
  annotation "device/model",
             description: "Vendor and model",
             title: "Model"
  annotation "device/serial",
             description: "Serial number",
             title: "Serial"
  annotation "device/rack",
             description: "Rack and height units, e.g. B12 U20-21",
             title: "Rack"

  relation :locatedAt, :technologyFacilities, :TechnologyFacility
  relation :connectedTo, :technologyDevices, :TechnologyDevice
  relation :composedOf, :technologyDevices, :TechnologyDevice
end
