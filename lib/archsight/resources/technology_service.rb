# frozen_string_literal: true

# TechnologyService supports the deployment of the application on a high level
class Archsight::Resources::TechnologyService < Archsight::Resources::Base
  include_annotations :git, :architecture, :generated

  description <<~MD
    Represents an explicitly defined piece of technology functionality.

    ## ArchiMate Definition

    **Layer:** Technology
    **Aspect:** Behavior

    A technology service represents an explicitly defined piece of functionality exposed
    by technology nodes. It provides platform-level capabilities that support the deployment
    and operation of application components.

    ## Usage

    Use TechnologyService to represent:

    - Cloud platform services (AWS EC2, Azure VMs)
    - Container orchestration services
    - Managed database services
    - CI/CD pipeline services
    - Monitoring and logging platforms

    ## Not this kind

    - The software that provides it is `TechnologySystemSoftware`, the machines are `TechnologyNode`s
    - A network is a `TechnologyCommunicationNetwork`; a physical link is `TechnologyEquipment`
    - One service for all sites, `locatedAt` each `TechnologyFacility`, not a copy per site

    Which kind to pick: "Choosing the Kind: Infrastructure" in the modeling guide.

    ## Location

    A service that runs in several data centers is one service that is `locatedAt` each `TechnologyFacility`, not one service
    per site.

    ## Physical realization

    A service is `realizedBy` the `TechnologyEquipment` it runs over: a backbone network service is realized by the links
    between the facilities (`equipment/type: link`).

    ## Concept and implementation

    A service can `specialize` another service (ArchiMate specialization): the general service is the concept, the
    specific ones are its implementations, listed as incoming "specializes" on the concept's page. The target must be
    a TechnologyService and the chain must not form a cycle.
  MD

  icon "cloud"
  layer "technology"

  annotation "architecture/applicationSets",
             description: "Related ArgoCD ApplicationSets",
             title: "ApplicationSets",
             format: :markdown

  relation :suppliedBy, :technologyComponents, :TechnologySystemSoftware
  relation :specializes, :technologyServices, :TechnologyService
  relation :servedBy, :businessActors, :BusinessActor
  relation :locatedAt, :technologyFacilities, :TechnologyFacility
  relation :realizedBy, :technologyEquipment, :TechnologyEquipment
  relation :realizes, :motivationRequirements, :MotivationRequirement
  relation :partiallyRealizes, :motivationRequirements, :MotivationRequirement
  relation :plans, :motivationRequirements, :MotivationRequirement
  relation :evidencedBy, :complianceEvidences, :ComplianceEvidence
end
