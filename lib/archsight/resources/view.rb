# frozen_string_literal: true

# View represents a saved query with custom table display options
class Archsight::Resources::View < Archsight::Resources::Base
  include_annotations :architecture

  description <<~MD
    Represents a saved query with customizable display options.

    ## Definition

    A View is a tool-specific resource type that saves a query and its display configuration.
    Views allow users to create reusable perspectives on the architecture data, with custom
    column selections and sorting options.

    ## Usage

    Use View to create:

    - Compliance dashboards
    - Team-specific resource lists
    - Audit views
    - Custom reports
    - Filtered resource tables
  MD

  icon "view-grid"
  layer "other"

  annotation "view/query",
             description: 'Query string to execute (e.g., "ApplicationService: backup/mode == \"none\"")',
             title: "Query",
             sidebar: false

  annotation "view/fields",
             description: "Comma-separated list of annotation fields or @components to display as columns. " \
                          "Components: @activity, @git, @jira, @languages, @owner, @repositories, @status",
             title: "Display Fields",
             sidebar: false

  annotation "view/type",
             description: "Display type for results",
             title: "Display Type",
             enum: %w[list:name list:name+kind],
             sidebar: false

  annotation "view/sort",
             description: 'Comma-separated list of fields to sort by. Prefix with - for descending (e.g., "-scc/language/Go/loc,name"). Special fields: name, kind',
             title: "Sort Fields",
             sidebar: false
end
