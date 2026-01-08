# frozen_string_literal: true

require "uri"

# TechnologyArtifact usually a source code repository or container
class Archsight::Resources::TechnologyArtifact < Archsight::Resources::Base
  include_annotations :git, :architecture, :generated

  description <<~MD
    Represents a source code repository or container artifact.

    ## ArchiMate Definition

    **Layer:** Technology
    **Aspect:** Passive Structure

    An artifact represents a piece of data that is used or produced in a software development
    process, or by deployment and operation of an IT system. In this tool, artifacts primarily
    represent source code repositories.

    ## Usage

    Use TechnologyArtifact to represent:

    - Git repositories
    - Container images
    - Build artifacts
    - Configuration packages
  MD

  icon "puzzle"
  layer "technology"

  # Artifact classification
  annotation "artifact/type",
             description: "Type of technology artifact",
             title: "Artifact Type",
             enum: %w[repo container chart deb rpm]

  # Dynamic annotations (patterns with *)
  annotation "link/*",
             description: "Documentation and resource links",
             sidebar: false
  annotation "scc/language/*/loc",
             description: "Lines of code per programming language",
             sidebar: false
  annotation "scc/languages",
             description: "Comma-separated list of programming languages",
             filter: :list,
             title: "Languages",
             sidebar: false
  annotation "scc/estimatedCost",
             description: "Estimated project cost",
             title: "Estimated Cost",
             type: Float
  annotation "scc/estimatedScheduleMonths",
             description: "Estimated schedule in months",
             title: "Estimated Schedule",
             type: Float
  annotation "scc/estimatedPeople",
             description: "Estimated number of people required",
             title: "Estimated People",
             type: Float
  annotation "activity/commits",
             description: "Monthly commit counts (comma-separated, oldest to newest)",
             title: "Commits",
             sidebar: false
  annotation "activity/contributors",
             description: "Monthly unique contributor counts (comma-separated, oldest to newest)",
             title: "Contributors",
             sidebar: false
  annotation "activity/status",
             description: "Repository activity status",
             title: "Activity Status",
             enum: %w[active abandoned bot-only archived],
             list: true
  annotation "activity/busFactor",
             description: "Bus factor assessment",
             title: "Bus Factor",
             enum: %w[high medium low unknown],
             list: true
  annotation "activity/createdAt",
             description: "Date of first commit (repository creation)",
             title: "Created",
             type: Time
  annotation "agentic/tools",
             description: "Agentic tools detected in repository",
             title: "Agentic Tools",
             filter: :list,
             enum: %w[claude cursor aider github-copilot agents none]
  annotation "workflow/platforms",
             description: "CI/CD workflow platforms",
             title: "Workflow Platforms",
             filter: :list,
             enum: %w[github-actions gitlab-ci makefile none]
  annotation "workflow/types",
             description: "CI/CD workflow types",
             title: "Workflow Types",
             filter: :list,
             enum: %w[build test unit-test integration-test smoke-test deploy lint security-scan dependency-update
                      ticket-creation none]

  # Urls for for git, chart repo, container repo
  annotation "repository/artifacts",
             description: "Types of artifacts produced by this repository",
             title: "Artifacts",
             filter: :list,
             enum: %w[container chart debian rpm binary none]
  annotation "repository/git",
             description: "Git repository URL",
             title: "Git Repository",
             type: URI
  annotation "repository/chart",
             description: "Helm chart repository URL",
             title: "Chart Repository",
             type: URI
  annotation "repository/container",
             description: "Container registry URL",
             title: "Container Repository",
             type: URI
  annotation "repository/visibility",
             description: "Repository visibility classification",
             title: "Visibility",
             enum: %w[internal open-source public]
  annotation "deployment/images",
             description: "OCI container image names published by this repository",
             title: "Container Images",
             sidebar: false,
             filter: :list
  annotation "deployment/privileges/user",
             description: "User privilege level for deployment",
             title: "Deployment User Privileges",
             enum: %w[as-root as-root-gvisor as-user-gvisor as-user-reduced-priviledges
                      as-user-reduced-priviledges-gvisor]
  annotation "deployment/privileges/container",
             description: "Container privilege level",
             title: "Deployment Container Privileges",
             enum: %w[unprivileged privileged]

  # Contributor metrics (unique counts, stored during import)
  annotation "activity/contributors/6m",
             title: "Contributors (6 months)",
             description: "Unique contributors in the last 6 months",
             type: Integer
  annotation "activity/contributors/total",
             title: "Contributors (total)",
             description: "Total unique contributors",
             type: Integer

  relation :servedBy, :technologyComponents, :TechnologyArtifact
  relation :suppliedBy, :technologyComponents, :TechnologyService
  relation :maintainedBy, :businessActors, :BusinessActor
  relation :contributedBy, :businessActors, :BusinessActor
end
