# Archsight's own architecture, as an .asd diagram.
#   archsight diagram examples/diagrams/archsight.asd

theme "compact"

actor "maintainer" { label "Maintainer" }
actor "browser" { label "Browser" }
actor "assistant" { label "AI assistant" }

stack "archsight" {
  label "Archsight"

  layer "interfaces" {
    label "Interfaces"

    application "cli" { label "CLI (Thor)" }

    group "web" {
      label "Web"
      application "spa" { label "Web UI (Vue SPA)" }
      api "api" { label "REST API" }
      component "editor" { label "Resource editor" }
    }

    api "mcp" { label "MCP server (SSE)" }
  }

  layer "features" {
    label "Features"

    group "cli_commands" {
      label "CLI commands"
      component "linter" { label "Linter" }
      component "template" { label "Template" }
      component "diagram" { label "Diagram renderer (.asd)" }
    }

    group "query_system" {
      label "Query + analysis"
      component "query" { label "Query engine" }
      component "analysis" { label "Analysis executor" }
    }

    group "rendering" {
      label "Rendering"
      component "graphviz" { label "GraphViz DOT" }
      component "documentation" { label "Documentation" }
    }

    group "import_system" {
      label "Import system"
      component "executor" { label "Import executor" }
      component "handlers" { label "Handlers (GitHub, GitLab, Jira, REST API)" }
      component "graphers" { label "Language graphers (Go, Ruby, Python, ...)" }
      component "writer" { label "Shared file writer" }
    }
  }

  layer "core" {
    label "Core"
    component "database" { label "Database" }
    component "resources" { label "Resources (ArchiMate kinds)" }
    component "annotations" { label "Annotations + computed values" }
  }
}

database "yaml" { label "YAML resources" }
database "generated" { label "Generated resources" }
application "sources" { label "GitHub / GitLab / Jira" }

maintainer -> cli
browser -> spa
assistant -> mcp

spa -> api
spa -> editor
api -> query
api -> graphviz
api -> documentation
mcp -> query
mcp -> analysis
mcp -> documentation
editor -> database

cli -> linter
cli -> template
cli -> diagram
cli -> analysis
cli -> executor

query -> database
analysis -> database
graphviz -> database
linter -> database
template -> resources

executor -> handlers
executor -> graphers
handlers -> sources
handlers -> writer
graphers -> writer
writer -> generated

database -> resources
database -> annotations
database -> yaml
database -> generated
