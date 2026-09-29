# Archsight's own architecture, as an .asd diagram.
#   archsight diagram examples/diagrams/archsight.asd
#
# A boundary (the archsight process) holding a stack of layers: frontends
# run on top of APIs, which run on top of the features, which run on the core. The import system
# is a stack of its own inside the features layer; the web subsystem puts its
# web server in front of its components.

theme "compact"

stack {
  gap "500%"
  layer {
    actor "maintainer" { label "Maintainer" }
    actor "browser" { label "Browser" }
    actor "assistant" { label "AI assistant" }
  }

  boundary "archsight" {
    label "Archsight"

    stack {
      gap "500%"
      layer "frontends" {
        application "cli" { label "CLI (Thor)" }
        application "spa" { label "Web UI (Vue SPA)" }
      }

      layer "apis" {
        api "api" { label "REST API" }
        api "mcp" { label "MCP server (SSE)" }
      }

      layer "features" {
        stack "import" {
          gap "500%"
          label "Import system"
          component "executor" { label "Import executor" }
          component "contract" { label "Handler contract" }
          layer {
            component "handlers" { label "Handlers (GitHub, GitLab, Jira, REST API)" }
            component "graphers" { label "Language graphers (Go, Ruby, Python, ...)" }
          }
          component "writer" { label "Shared file writer" }
        }

        layer "cli_subsystem" {
          label "CLI subsystem"
          component "linter" { label "Linter" }
          component "template" { label "Template generator" }
          component "diagram" { label "Diagram renderer (.asd)" }
        }

        stack "web_subsystem" {
          gap "500%"
          label "Web subsystem"
          component "webserver" { label "Web server (Puma + Sinatra)" }
          layer {
            component "editor" { label "Resource editor" }
            component "query" { label "Query engine" }
            component "analysis" { label "Analysis executor" }
            component "graphviz" { label "GraphViz DOT" }
            component "docs" { label "Documentation" }
          }
        }
      }

      layer "storage" {
        component "database" { label "Database" }
      }

      layer "model" {
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
api -> webserver
mcp -> webserver
webserver -> editor
webserver -> query
webserver -> analysis
webserver -> graphviz
webserver -> docs

cli -> linter
cli -> template
cli -> diagram
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
