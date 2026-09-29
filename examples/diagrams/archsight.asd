# Archsight's own architecture, as an .asd diagram.
#   archsight diagram examples/diagrams/archsight.asd
#
# A boundary (the archsight process) holding a stack of layers: frontends
# run on top of APIs, which run on top of the features, which run on the core. The import system
# is a stack of its own inside the features layer.

theme "compact"

stack {
  layer {
    actor "maintainer" { label "Maintainer" }
    actor "browser" { label "Browser" }
    actor "assistant" { label "AI assistant" }
  }

  boundary "archsight" {
    label "Archsight"

    stack {
      layer "frontends" {
        application "cli" { label "CLI (Thor)" }
        application "spa" { label "Web UI (Vue SPA)" }
      }

      layer "apis" {
        api "api" { label "REST API" }
        api "mcp" { label "MCP server (SSE)" }
      }

      layer "features" {
        component "linter" { label "Linter" }
        component "template" { label "Template generator" }
        component "diagram" { label "Diagram renderer (.asd)" }
        component "editor" { label "Resource editor" }
        component "query" { label "Query engine" }
        component "analysis" { label "Analysis executor" }
        component "graphviz" { label "GraphViz DOT" }
        component "docs" { label "Documentation" }

        stack "import" {
          label "Import system"
          component "executor" { label "Import executor" }
          component "contract" { label "Handler contract" }
          layer {
            component "handlers" { label "Handlers (GitHub, GitLab, Jira, REST API)" }
            component "graphers" { label "Language graphers (Go, Ruby, Python, ...)" }
          }
          component "writer" { label "Shared file writer" }
        }
      }

      layer "core" {
        component "database" { label "Database" }
        component "resources" { label "Resources (ArchiMate kinds)" }
        component "annotations" { label "Annotations + computed values" }
      }
    }
  }

  layer {
    application "sources" { label "GitHub / GitLab / Jira" }
    database "yaml" { label "YAML resources" }
    database "generated" { label "Generated resources" }
  }
}

maintainer -> cli
browser -> spa
assistant -> mcp

spa -> api { label "HTTPS / JSON" }
api -> query
api -> graphviz
api -> docs
api -> editor
mcp -> query
mcp -> analysis
mcp -> docs

cli -> linter
cli -> template
cli -> diagram
cli -> analysis
cli -> executor

executor -> handlers
executor -> graphers
handlers -> contract { relation "implements" }
graphers -> contract { relation "implements" }

query -> database
analysis -> database
graphviz -> database
linter -> database
editor -> database
template -> resources
database -> resources
database -> annotations
database -> yaml { label "loads" }

dataflow "import" {
  hop "sources"
  hop "handlers"
  hop "writer"
  hop "generated"
  color "#1a56db"
  label "import"
}
