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

  # Handler selection: a built-in handler or one the resources repository registers (import/handlerPath)
  annotation "import/handler",
             description: "Name of the handler that executes this import: a built-in one or one registered by the file " \
                          "in import/handlerPath",
             title: "Handler",
             summary: true,
             filter: :word,
             validator: lambda { |value|
               require "archsight/import/handler_loader"
               Archsight::Import::HandlerLoader.load_builtin!
               next if Archsight::Import::Registry[value]

               "unknown import handler '#{value}'. Registered: #{Archsight::Import::Registry.handlers.sort.join(", ")}; " \
                 "a handler of the resources repository needs import/handlerPath"
             }

  annotation "import/handlerPath",
             description: "Ruby file of a handler that lives in the resources repository, relative to the resources " \
                          "root (e.g., 'importers/deployments.rb'). It registers the name used in import/handler.",
             title: "Handler Path"

  annotation "import/dependsOn",
             description: "Imports that must run first, by name or glob pattern (e.g., 'Import:Repo:*'), comma " \
                          "separated. Adds to the dependency on the import that generated this one.",
             title: "Depends On",
             filter: :list,
             sidebar: false

  # Output configuration
  annotation "import/outputPath",
             description: "Output file path relative to resources root (e.g., 'imports/generated/gitlab.yaml')",
             title: "Output Path"

  annotation "generated/inputsHash",
             description: "Hash of the files matched by import/config/inputs at the last run (for change detection)",
             title: "Inputs Hash",
             sidebar: false,
             editor: false

  annotation "generated/outputs",
             description: "Files the last run wrote, relative to the resources root",
             title: "Outputs",
             filter: :list,
             sidebar: false,
             editor: false

  # Control flags
  annotation "import/enabled",
             description: "Whether this import is enabled",
             title: "Enabled",
             enum: %w[true false],
             summary: true

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

  # Generated resources relations - auto-tracked by handlers
  # Dependencies are derived from the inverse of generates - if A generates B, B depends on A
  relation :generates, :technologyArtifacts, :TechnologyArtifact
  relation :generates, :applicationInterfaces, :ApplicationInterface
  relation :generates, :dataObjects, :DataObject
  relation :generates, :imports, :Import
  relation :generates, :businessActors, :BusinessActor
end
