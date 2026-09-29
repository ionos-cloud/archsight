# Archsight's own architecture, as an .asd diagram.
#   archsight diagram examples/diagrams/archsight.asd

actor "maintainer" { label "Maintainer / AI assistant" }

group "archsight" {
  label "Archsight"

  layer "interfaces" {
    label "Interfaces"
    application "cli" { label "CLI (Thor)" }
    application "web" { label "Web UI (Vue SPA)" }
    api "rest" { label "REST API" }
    api "mcp" { label "MCP server" }
  }

  layer "features" {
    label "Features"
    component "linter" { label "Linter" }
    component "graphviz" { label "GraphViz renderer" }
    component "diagram" { label "Diagram renderer (.asd)" }
    component "query" { label "Query engine" }
  }

  group "core" {
    label "Core"
    component "database" { label "Database" }
    component "resources" { label "Resources" }
  }
}

database "yaml" { label "YAML resources" }

maintainer -> cli
maintainer -> web
maintainer -> mcp
cli -> linter
cli -> diagram
web -> rest
rest -> graphviz
rest -> query
mcp -> query
linter -> database
graphviz -> database
query -> database
database -> resources
resources -> yaml
