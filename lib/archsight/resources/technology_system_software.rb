# frozen_string_literal: true

# TechnologySystemSoftware serves the TechnologySystemSoftware
class Archsight::Resources::TechnologySystemSoftware < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a logical infrastructure component that serves application components.

    ## ArchiMate Definition

    **Layer:** Technology
    **Aspect:** Active Structure

    System software represents software that provides or contributes to an environment
    for storing, executing, and using software or data deployed within it. Logical
    technology components represent abstract infrastructure units.

    ## Usage

    Use TechnologySystemSoftware to represent:

    - Database clusters
    - Message broker clusters
    - Cache clusters
    - Load balancers
    - Service meshes

    ## Not this kind

    - The machine it runs on is a `TechnologyNode`
    - What consumers use from it is a `TechnologyService`
    - A routing stack that implements a network realizes a `TechnologyCommunicationNetwork`

    Which kind to pick: "Choosing the Kind: Infrastructure" in the modeling guide.

    ## Location

    System software is `locatedAt` the `TechnologyFacility` (or facilities) it runs in.

    ## Deployment

    System software `assignedTo` the artifacts it executes (ArchiMate assignment), written on the system software.
    The artifact's page shows it as incoming "deployed on".

    ## Concept and implementation

    System software can `specialize` other system software (ArchiMate specialization): the general one is the
    concept, the specific ones are its implementations, listed as incoming "specializes" on the concept's page.
    A platform that bundles components is `composedOf` them (ArchiMate composition). Both only point at system
    software, and neither may form a cycle.
  MD

  icon "terminal-tag"
  layer "technology"

  relation :realizedBy, :technologyComponents, :TechnologyNode
  relation :specializes, :technologySystemSoftware, :TechnologySystemSoftware
  relation :composedOf, :technologySystemSoftware, :TechnologySystemSoftware
  relation :assignedTo, :technologyArtifacts, :TechnologyArtifact
  relation :realizedThrough, :technologyArtifacts, :TechnologyArtifact
  relation :exposes, :applicationInterfaces, :ApplicationInterface
  relation :dependsOn, :applicationInterfaces, :ApplicationInterface
  relation :realizes, :motivationRequirements, :MotivationRequirement
  relation :partiallyRealizes, :motivationRequirements, :MotivationRequirement
  relation :plans, :motivationRequirements, :MotivationRequirement
  relation :evidencedBy, :complianceEvidences, :ComplianceEvidence
  relation :locatedAt, :technologyFacilities, :TechnologyFacility
end
