# frozen_string_literal: true

# TechnologyCommunicationNetwork represents a logical network that connects nodes and system software
class Archsight::Resources::TechnologyCommunicationNetwork < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a logical network: a management network, the public network, an overlay such as BGP-EVPN, a VPN or a
    network that supports a metro region.

    ## ArchiMate Definition

    **Layer:** Technology
    **Aspect:** Active Structure

    A communication network is a set of structures and behaviors that connects devices or system software for
    transmission, routing and reception of data.

    ## Usage

    Use TechnologyCommunicationNetwork to represent:

    - Underlay networks (the routed fabric) and overlay networks that run on them (BGP-EVPN, VXLAN)
    - Management, storage and public networks
    - VPNs and mesh networks (one network with `network/topology: mesh`, not one element per pair of sites)
    - Networks that support a metro region, made of the networks of its sites

    Do not model a network per customer or tenant: the overlay is one network, its tenants are instances of it.
    Physical links and fabrics are `TechnologyEquipment`.

    ## Not this kind

    - Cables, fibre routes and switch fabrics are `TechnologyEquipment`; the network is `realizedBy` them
    - The routing or VPN software is `TechnologySystemSoftware` that realizes the network
    - A network offered as a product to consumers can additionally be a `TechnologyService` realized by it
    - No network per tenant, no element per pair of sites in a mesh

    Which kind to pick: "Choosing the Kind: Infrastructure" in the modeling guide.

    ## How it connects

    - A network is `composedOf` other networks (a metro network of its site networks); the target must be a network
      and the chain must not form a cycle
    - A network `specializes` a more general network (the concept "management network" and its implementations)
    - A network is `servedBy` the network it runs over: the underlay serves the overlay, a VPN is served by the
      network it tunnels through
    - A network is `locatedAt` the facilities and locations it spans, many of them for one network
    - A network is `realizedBy` the `TechnologyEquipment` it runs over and the `TechnologySystemSoftware` that implements it
      (the routing stack, the VPN software)
    - An overlay that software builds is `realizedBy` that `ApplicationComponent` or `ApplicationService` (an SDN agent,
      a network operator, a load-balancer controller), also when the software runs on the nodes the network serves
    - A `TechnologyNode` is `servedBy` the networks it is attached to; the network page lists them
    - A network is `realizedBy` the `TechnologyDevice`s that build it (its switches and routers) and `connects` the
      devices attached to it (servers, firewalls, appliances). Both are written on the network, so a switch that is
      also attached to the network it builds closes no cycle
  MD

  icon "network"
  layer "technology"

  annotation "network/type",
             description: "Role of the network",
             title: "Network Type",
             enum: %w[underlay overlay management public vpn other],
             filter: :word,
             summary: true

  annotation "network/topology",
             description: "Shape of the network",
             title: "Topology",
             enum: %w[mesh hub-and-spoke point-to-point ring other],
             filter: :word,
             summary: true

  relation :composedOf, :technologyCommunicationNetworks, :TechnologyCommunicationNetwork
  relation :specializes, :technologyCommunicationNetworks, :TechnologyCommunicationNetwork
  relation :servedBy, :technologyCommunicationNetworks, :TechnologyCommunicationNetwork
  relation :locatedAt, :technologyFacilities, :TechnologyFacility
  relation :locatedAt, :locations, :Location
  relation :realizedBy, :technologyEquipment, :TechnologyEquipment
  relation :realizedBy, :technologyDevices, :TechnologyDevice
  relation :connects, :technologyDevices, :TechnologyDevice
  relation :realizedBy, :technologySystemSoftware, :TechnologySystemSoftware
  relation :realizedBy, :applicationComponents, :ApplicationComponent
  relation :realizedBy, :applicationServices, :ApplicationService
end
