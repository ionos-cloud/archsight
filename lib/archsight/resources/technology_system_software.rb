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
  MD

  icon "terminal-tag"
  layer "technology"

  relation :realizedBy, :technologyComponents, :TechnologyNode
  relation :realizedThrough, :technologyArtifacts, :TechnologyArtifact
  relation :exposes, :applicationInterfaces, :ApplicationInterface
  relation :dependsOn, :applicationInterfaces, :ApplicationInterface
end
