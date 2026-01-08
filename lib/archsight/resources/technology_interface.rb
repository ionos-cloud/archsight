# frozen_string_literal: true

# TechnologyInterface is the backing of an applicationInterface
class Archsight::Resources::TechnologyInterface < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a point of access where technology services are made available.

    ## ArchiMate Definition

    **Layer:** Technology
    **Aspect:** Active Structure (external)

    A technology interface represents a point of access where technology services offered
    by a node can be accessed. It provides the technical implementation backing for
    application interfaces.

    ## Usage

    Use TechnologyInterface to represent:

    - Network endpoints (IP:port combinations)
    - Protocol bindings (HTTP, gRPC, AMQP)
    - Load balancer virtual IPs
    - Service mesh endpoints
    - DNS entries
  MD

  icon "data-transfer-both"
  layer "technology"

  relation :suppliedBy, :technologyComponents, :TechnologyService
end
