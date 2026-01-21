# frozen_string_literal: true

# Analysis represents a declarative analysis script that validates or reports on architecture resources
class Archsight::Resources::Analysis < Archsight::Resources::Base
  include_annotations :generated

  description <<~MD
    Represents a declarative analysis script for validating or reporting on architecture resources.

    ## Definition

    An Analysis is a tool-specific resource type that defines Ruby scripts to run
    against the architecture database. Scripts execute in a sandboxed environment
    with access to instance traversal, annotation access, and reporting methods.

    ## Usage

    Use Analysis to represent:

    - Validation rules (team ownership, naming conventions)
    - Architecture compliance checks
    - Metrics collection and aggregation
    - Custom reports and dashboards

    ## Script Environment

    Scripts have access to:

    - `each_instance(kind)` - iterate over all instances of a kind
    - `instances(kind)` - get array of instances
    - `instance(kind, name)` - get specific instance
    - `outgoing(inst, kind)` / `incoming(inst, kind)` - relation traversal
    - `outgoing_transitive(inst, kind)` / `incoming_transitive(inst, kind)` - transitive relations
    - `annotation(inst, key)` - get annotation value
    - `name(inst)` / `kind(inst)` - get instance metadata
    - `query(query_string)` - execute a query
    - `report(data, title:)` - output findings
    - `warning(msg)` / `error(msg)` / `info(msg)` - log messages
  MD

  icon "clipboard-check"
  layer "other"

  # Handler selection (for future extensibility)
  annotation "analysis/handler",
             description: "Script handler type (only 'ruby' currently supported)",
             title: "Handler",
             enum: %w[ruby]

  # Script content
  annotation "analysis/script",
             description: "Ruby script to execute in sandboxed environment",
             title: "Script",
             sidebar: false

  # Description
  annotation "analysis/description",
             description: "Human-readable description of what this analysis validates",
             title: "Description"

  # Execution configuration
  annotation "analysis/timeout",
             description: "Maximum execution time (e.g., '30s', '5m')",
             title: "Timeout"

  # Output configuration
  annotation "analysis/output",
             description: "Output mode for results",
             title: "Output",
             enum: %w[console file]

  annotation "analysis/outputPath",
             description: "File path for output (when output mode is 'file')",
             title: "Output Path",
             sidebar: false

  # Enabled flag
  annotation "analysis/enabled",
             description: "Whether this analysis is enabled",
             title: "Enabled",
             enum: %w[true false]

  # Pattern annotation for custom configuration
  annotation "analysis/config/*",
             description: "Custom configuration values for the analysis script",
             sidebar: false

  # Dependency relation (analyses can depend on other analyses or imports)
  relation :dependsOn, :imports, :Import
  relation :dependsOn, :analyses, :Analysis
end
