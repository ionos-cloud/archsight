# frozen_string_literal: true

# TechnologyNode represents physical infrastructure (VMs, servers, Kubernetes nodes)
class Archsight::Resources::TechnologyNode < Archsight::Resources::Base
  include_annotations :git, :architecture

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
  MD

  icon "server-connection"
  layer "technology"

  annotation "infrastructure/type",
             description: "Type of infrastructure node",
             title: "Infrastructure Type",
             enum: %w[vm bare-metal kubernetes-node network-appliance storage-array],
             list: true

  relation :realizes, :businessConstraints, :BusinessConstraint
  relation :servedBy, :technologyServices, :TechnologyService
  relation :servedBy, :businessActors, :BusinessActor
end
