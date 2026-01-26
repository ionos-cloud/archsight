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
  MD

  icon "cloud"
  layer "technology"

  annotation "architecture/applicationSets",
             description: "Related ArgoCD ApplicationSets",
             title: "ApplicationSets",
             format: :markdown

  relation :suppliedBy, :technologyComponents, :TechnologySystemSoftware
  relation :servedBy, :businessActors, :BusinessActor
end
