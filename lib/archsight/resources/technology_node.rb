# frozen_string_literal: true

# TechnologyNode represents physical infrastructure (VMs, servers, Kubernetes nodes)
class Archsight::Resources::TechnologyNode < Archsight::Resources::Base
  include_annotations :git, :architecture, :asset, :risk

  description <<~MD
    Represents physical infrastructure hosting application components.

    ## ArchiMate Definition

    **Layer:** Technology
    **Aspect:** Active Structure

    A node represents a computational or physical resource that hosts, manipulates, or
    interacts with other computational or physical resources. In cloud contexts, this
    includes compute instances, storage systems, and network equipment.

    ## Usage

    Use TechnologyNode to represent:

    - Virtual machines
    - Bare metal servers
    - Kubernetes nodes
    - Network appliances
    - Storage arrays

    ## Not this kind

    - A building or data center is a `TechnologyFacility`; a rack or fabric is `TechnologyEquipment`
    - Software running on the node (database, routing stack) is `TechnologySystemSoftware`
    - One node per host role is often enough; many identical hosts are one node `locatedAt` several facilities
    - A single physical machine whose room or cabling matters is a `TechnologyDevice`; the node is `realizedBy` it

    Which kind to pick: "Choosing the Kind: Infrastructure" in the modeling guide.

    ## Location

    A node is `locatedAt` the `TechnologyFacility` (or facilities) it stands in; see `TechnologyFacility`.

    ## Networks

    A node is `servedBy` the `TechnologyCommunicationNetwork`s it is attached to (management, public, an overlay).

    ## Physical realization

    A node is `realizedBy` the `TechnologyEquipment` it consists of or stands on (a router on its rack); see `TechnologyEquipment`.
    A logical node (a host role, "the hypervisors of the platform") is `realizedBy` the `TechnologyDevice`s, the
    physical machines, that make it up.

    ## Concept and implementation

    A node can `specialize` another node (ArchiMate specialization): the general node is the concept (a regional
    cluster), the specific nodes are its implementations. The concept's page lists them as incoming "specializes".
    A node made of other nodes (a cluster of hosts) is `composedOf` them (ArchiMate composition). Both only point at
    nodes, and neither may form a cycle.

    ## Deployment

    A node `assignedTo` the artifacts that are deployed on it (ArchiMate assignment): the image it boots, the
    packages installed on it. The relation is written on the node, which owns the deployment; the artifact's page
    shows the nodes as incoming "deployed on".

    ## Security and risk modelling

    A node is the typical asset of a vulnerability assessment: a scan result is a `MotivationAssessment` of type
    `vulnerability` that `assesses` the nodes it was found on (one vulnerability, many nodes) and `influences` the
    loss events it makes possible. Set the `asset/*` profile and `risk/domain` to group nodes by context.
  MD

  icon "server-connection"
  layer "technology"

  annotation "infrastructure/type",
             description: "Type of infrastructure node",
             title: "Infrastructure Type",
             enum: %w[vm bare-metal kubernetes-node network-appliance storage-array],
             summary: true

  relation :realizes, :motivationConstraints, :MotivationConstraint
  relation :servedBy, :technologyServices, :TechnologyService
  relation :servedBy, :technologyCommunicationNetworks, :TechnologyCommunicationNetwork
  relation :servedBy, :businessActors, :BusinessActor
  relation :locatedAt, :technologyFacilities, :TechnologyFacility
  relation :realizedBy, :technologyEquipment, :TechnologyEquipment
  relation :realizedBy, :technologyDevices, :TechnologyDevice
  relation :specializes, :technologyNodes, :TechnologyNode
  relation :composedOf, :technologyNodes, :TechnologyNode
  relation :assignedTo, :technologyArtifacts, :TechnologyArtifact
end
