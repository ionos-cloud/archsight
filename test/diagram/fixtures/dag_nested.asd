# Ranks at every level (see "Ranks" in the README): the top-level groups
# form a DAG four ranks deep, so `auto` stacks them top to bottom, and
# each group arranges its own children its own way.

# `ranks "off"`: the plain force layout, for comparison.
group "frontend" {
  label "Frontend"
  ranks "off"
  component "web" { label "Web App" }
  component "mobile" { label "Mobile App" }
  component "bff" { label "Mobile BFF" }
}

# `auto`: a DAG at least three ranks deep, so ranked top to bottom.
group "services" {
  label "Services"
  component "gateway" { label "API Gateway" }
  component "orders" { label "Orders" }
  component "catalog" { label "Catalog" }
  component "payments" { label "Payments" }
  component "pricing" { label "Pricing" }
  component "events" { label "Events" }
}

# `ranks "right"`: a pipeline, ranked left to right.
group "data" {
  label "Data Pipeline"
  ranks "right"
  component "ingest" { label "Ingest" }
  component "clean" { label "Clean" }
  component "enrich" { label "Enrich" }
  component "store" { label "Store" }
  component "archive" { label "Archive" }
}

# `ranks "on"` in a stack: ranked top to bottom like any stack, but
# equal-rank children side by side instead of one row each.
stack "platform" {
  label "Platform"
  ranks "on"
  component "db" { label "DB Driver" }
  component "queue" { label "Queue Client" }
  component "config" { label "Config" }
  component "logging" { label "Logging" }
  component "runtime" { label "Runtime" }
}

web -> gateway
mobile -> bff
bff -> gateway

gateway -> orders
gateway -> catalog
orders -> payments
orders -> pricing
catalog -> pricing
payments -> events
orders -> events

events -> ingest
ingest -> clean
clean -> enrich
enrich -> store
clean -> archive

store -> db
events -> queue
db -> config
db -> logging
queue -> logging
config -> runtime
logging -> runtime
