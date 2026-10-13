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

    ## Location

    A node is `locatedAt` the `Facility` (or facilities) it stands in; see `Facility`.

    ## Networks

    A node is `servedBy` the `CommunicationNetwork`s it is attached to (management, public, an overlay).

    ## Physical realization

    A node is `realizedBy` the `Equipment` it consists of or stands on (a router on its rack); see `Equipment`.

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
  relation :servedBy, :communicationNetworks, :CommunicationNetwork
  relation :servedBy, :businessActors, :BusinessActor
  relation :locatedAt, :facilities, :Facility
  relation :realizedBy, :equipment, :Equipment
  relation :specializes, :technologyNodes, :TechnologyNode
  relation :composedOf, :technologyNodes, :TechnologyNode
  relation :assignedTo, :technologyArtifacts, :TechnologyArtifact
end
