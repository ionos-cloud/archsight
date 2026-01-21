# frozen_string_literal: true

# Import represents a data import task that generates architecture resources
class Archsight::Resources::Import < Archsight::Resources::Base
  include_annotations :generated

  description <<~MD
    Represents an import task that generates architecture resources.

    ## Definition

    An Import is a tool-specific resource type that defines how to synchronize
    external data sources (GitLab, GitHub, ArgoCD, etc.) into the architecture
    database. Imports can depend on other imports to ensure proper execution order.

    ## Usage

    Use Import to represent:

    - Repository synchronization tasks
    - API data imports
    - Cluster discovery
    - External system integration

    ## Multi-Stage Imports

    Imports can generate other Import resources, enabling multi-stage workflows:

    1. GitLab import runs, discovers repositories
    2. Generates Import resources for each repository
    3. Repository imports run after GitLab import completes
    4. Each repository import generates TechnologyArtifact resources
  MD

  icon "download"
  layer "other"

  # Handler selection
  annotation "import/handler",
             description: "Handler class name to execute this import",
             title: "Handler", enum: %w[
               gitlab github repository
               rest-api rest-api-index
               jira-discover jira-metrics
             ]

  # Output configuration
  annotation "import/outputPath",
             description: "Output file path relative to resources root (e.g., 'imports/generated/gitlab.yaml')",
             title: "Output Path"

  # Control flags
  annotation "import/enabled",
             description: "Whether this import is enabled",
             title: "Enabled",
             enum: %w[true false]

  annotation "import/priority",
             description: "Execution priority (lower runs first among ready imports)",
             title: "Priority",
             type: Integer

  annotation "import/cacheTime",
             description: "Cache duration (e.g., '30m', '1h', '24h', '7d'). Set to 'never' to always run.",
             title: "Cache Time"

  # Handler-specific configuration (pattern annotation)
  annotation "import/config/*",
             description: "Handler-specific configuration values",
             sidebar: false

  # Dependency relation
  relation :dependsOn, :imports, :Import
end
