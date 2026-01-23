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
  MD

  icon "usb"
  layer "application"

  # API
  annotation "api/responsiveness",
             description: "API 99th percentile responsiveness target",
             title: "API Responsiveness (99p)",
             enum: %w[10ms 100ms 1000ms 2s 5s 10s unresponsive]
  annotation "api/authenticationMethod",
             description: "API authentication method",
             title: "API Authentication Method",
             enum: ["none", "hard coded", "token", "oidc"]
  annotation "api/authenticationProvider",
             description: "API authentication provider",
             title: "API Authentication Provider",
             enum: %w[eiam cloud custom]
  annotation "api/authorization",
             description: "API authorization mechanism",
             title: "API Authorization",
             enum: ["none", "hard coded", "pbac", "abac", "rbac"]

  relation :servedBy, :technologyComponents, :TechnologyInterface
  relation :realizes, :businessConstraints, :BusinessConstraint
  relation :serves, :dataObjects, :DataObject
end
