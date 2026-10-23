# frozen_string_literal: true

# ApplicationInterface between ApplicationComponent
class Archsight::Resources::ApplicationInterface < Archsight::Resources::Base
  include_annotations :git, :architecture, :interface, :generated

  description <<~MD
    Represents a point of access where application services are made available.

    ## ArchiMate Definition

    **Layer:** Application
    **Aspect:** Active Structure (external)

    An application interface represents a point of access where application services
    are made available to a user, another application component, or a node. It exposes
    application behavior to the environment.

    ## Usage

    Use ApplicationInterface to represent:

    - REST APIs
    - GraphQL endpoints
    - gRPC services
    - Message queues (producer/consumer interfaces)
    - WebSocket endpoints

    ## Reachability

    An interface is `servedBy` the `TechnologyInterface` that carries it (a protocol, an authentication method) and
    by the `TechnologyCommunicationNetwork`s on which it can be reached, just as a `TechnologyNode` attaches to the
    networks it is on. Together with `api/authenticationMethod` this decides the exposure of the interface: an
    interface without authentication on an internal network is a different risk than on a network that
    internet-facing components attach to. The network page lists the interfaces as incoming "served by".

    Write the networks only when they are known. An interface without a network makes no claim about where it can
    be reached.
  MD

  icon "usb"
  layer "application"

  # API
  annotation "api/responsiveness",
             description: "API 99th percentile responsiveness target",
             title: "API Responsiveness (99p)",
             enum: %w[10ms 100ms 1000ms 2s 5s 10s unresponsive],
             summary: true
  annotation "api/authenticationMethod",
             description: "API authentication method",
             title: "API Authentication Method",
             enum: ["none", "hard coded", "token", "oidc"],
             summary: true
  annotation "api/authorization",
             description: "API authorization mechanism",
             title: "API Authorization",
             enum: ["none", "hard coded", "pbac", "abac", "rbac"]

  relation :servedBy, :technologyComponents, :TechnologyInterface
  relation :servedBy, :technologyCommunicationNetworks, :TechnologyCommunicationNetwork
  relation :realizes, :motivationConstraints, :MotivationConstraint
  relation :serves, :dataObjects, :DataObject
end
