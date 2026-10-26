# frozen_string_literal: true

# TechnologyDevice represents one physical machine: a server, switch, router, firewall, appliance or client machine
class Archsight::Resources::TechnologyDevice < Archsight::Resources::Base
  include_annotations :git, :architecture, :asset, :risk

  description <<~MD
    Represents one physical machine: a server, a switch, a router, a firewall, a terminal server, an appliance, or a
    client machine (a laptop, a workstation, a phone).

    ## ArchiMate Definition

    **Layer:** Technology
    **Aspect:** Active Structure

    A device is a physical IT resource upon which system software and artifacts may be stored or deployed for
    execution. It is a specialization of a node.

    ## Usage

    Use TechnologyDevice when the individual machine matters: which room it stands in, which switch it is cabled to,
    which machines a failure domain loses, which operating system and owner a workstation has.

    - One element per physical machine (name it after the host: "Device:Frankfurt:Server01")
    - A group of machines with one role ("the hypervisors of the platform") stays a logical `TechnologyNode` that is
      `realizedBy` its devices
    - A virtual chassis, a stack or a cluster pair is a device `composedOf` its member devices

    ## Client devices

    A developer workstation, a laptop, a thin client, a tablet or a phone is a device of the matching `device/type`;
    `device/os`, `device/osVersion` and `device/arch` say what it runs on, `device/ownership` whether the company
    owns it, `device/managed` whether it is centrally managed (MDM) and `device/encryption` whether the disk is
    encrypted. The vendor and product go into `device/model`, also for a hardened workstation that runs the user's
    operating system virtualized next to other isolated sessions: it is a `workstation`. The end of support is
    `lifecycle/endOfLifeAt`, a group of machines is a tag (`architecture/tags`).

    - Model the individual machine when it is inventoried (an MDM import can write them), otherwise one
      `TechnologyNode` per client platform ("Node:Workstation:macOS") `realizedBy` the devices
    - The operating system is `TechnologySystemSoftware` `realizedBy` that node; the image or packages it is
      installed from are `TechnologyArtifact`s the node is `assignedTo`. Each isolated session of a hardened
      workstation can be a node of its own, `realizedBy` the device
    - Network access: the platform node is `servedBy` the networks it uses (the office, the VPN), a single named
      machine is `connects`-ed by its network (the VPN it tunnels through, an isolated segment). A machine that
      reaches no network (air-gapped) has neither relation. The device itself does not point to networks: a network
      is `realizedBy` its switches, so the reverse arrow would close a cycle
    - Who uses it is the team or role (`servedBy`), not a person; a client device needs no room, `locatedAt` an
      office is optional

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
    - A device is `ownedBy` the team (`BusinessActor`) or `BusinessRole` responsible for operating it and `servedBy`
      the team it is dedicated to (ArchiMate serving: a test server held by one team); `device/purpose` says what for

    A device points to nothing above it: nodes, networks and equipment point down to the device, and the teams it
    points to point to nothing further, so the relations stay free of cycles.
  MD

  icon "server"
  layer "technology"

  annotation "device/type",
             description: "Kind of device",
             title: "Device Type",
             enum: %w[server switch router firewall terminal-server appliance laptop desktop workstation thin-client tablet mobile other],
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
  annotation "device/purpose",
             description: "What the device is dedicated to, e.g. kernel regression tests",
             title: "Purpose",
             filter: :word

  annotation "device/os",
             description: "Operating system family of a client device",
             title: "Operating System",
             enum: %w[windows macos linux freebsd openbsd netbsd android ios chromeos other],
             filter: :word,
             summary: true
  annotation "device/osVersion",
             description: "Operating system version, e.g. 15.1 or 24.04 LTS",
             title: "OS Version"
  annotation "device/arch",
             description: "CPU architecture",
             title: "Architecture",
             enum: %w[x86_64 arm64 riscv64 other],
             filter: :word
  annotation "device/ownership",
             description: "Who owns the device",
             title: "Ownership",
             enum: %w[company-owned leased byod],
             filter: :word
  annotation "device/managed",
             description: "Whether the device is managed centrally (MDM, configuration management)",
             title: "Managed",
             enum: %w[managed unmanaged],
             filter: :word
  annotation "device/encryption",
             description: "Whether the disk is encrypted",
             title: "Disk Encryption",
             enum: %w[enabled disabled],
             filter: :word

  relation :locatedAt, :technologyFacilities, :TechnologyFacility
  relation :connectedTo, :technologyDevices, :TechnologyDevice
  relation :composedOf, :technologyDevices, :TechnologyDevice
  relation :ownedBy, :businessActors, :BusinessActor
  relation :ownedBy, :businessRoles, :BusinessRole
  relation :servedBy, :businessActors, :BusinessActor
end
