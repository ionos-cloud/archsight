# frozen_string_literal: true

# CommunicationNetwork represents a logical network that connects nodes and system software
class Archsight::Resources::CommunicationNetwork < Archsight::Resources::Base
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

    Use CommunicationNetwork to represent:

    - Underlay networks (the routed fabric) and overlay networks that run on them (BGP-EVPN, VXLAN)
    - Management, storage and public networks
    - VPNs and mesh networks (one network with `network/topology: mesh`, not one element per pair of sites)
    - Networks that support a metro region, made of the networks of its sites

    Do not model a network per customer or tenant: the overlay is one network, its tenants are instances of it.
    Physical links and fabrics are `Equipment`.

    ## Not this kind

    - Cables, fibre routes and switch fabrics are `Equipment`; the network is `realizedBy` them
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
    - A network is `realizedBy` the `Equipment` it runs over and the `TechnologySystemSoftware` that implements it
      (the routing stack, the VPN software)
    - A `TechnologyNode` is `servedBy` the networks it is attached to; the network page lists them
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

  relation :composedOf, :communicationNetworks, :CommunicationNetwork
  relation :specializes, :communicationNetworks, :CommunicationNetwork
  relation :servedBy, :communicationNetworks, :CommunicationNetwork
  relation :locatedAt, :facilities, :Facility
  relation :locatedAt, :locations, :Location
  relation :realizedBy, :equipment, :Equipment
  relation :realizedBy, :technologySystemSoftware, :TechnologySystemSoftware
end
