component "cli" { label "CLI"; resource "Archsight:CLI:Commands" }
api "rest" { label "REST API"; resource "Archsight:Web:API" }
api "mcp" { label "MCP server"; resource "Archsight:Query:MCP" }
application "spa" { label "Web UI"; resource "Archsight:Web:Frontend" }
component "query" { label "Query engine"; resource "Archsight:Query:Engine" }
component "db" { label "Database"; resource "Archsight:Core:Database" }
component "res" { label "Resources"; resource "Archsight:Core:Resources" }
spa -> rest
rest -> query
mcp -> query
cli -> db
query -> db
db -> res
