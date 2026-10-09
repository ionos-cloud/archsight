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
  relation :servedBy, :businessActors, :BusinessActor
end
