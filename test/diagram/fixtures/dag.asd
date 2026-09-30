# A plain DAG: 30 components wired only by dependency edges, with no
# layers, stacks or groups. Every edge points "down" a level (apps ->
# services -> libraries -> core), so there are no cycles -- and since
# it's more than three ranks deep, `ranks "auto"` (the default) lays it
# out in ranks top to bottom (see "Ranks" in the README).

# Entry points
component "web" { label "Web App" }
component "mobile" { label "Mobile App" }
component "cli" { label "CLI" }
component "admin" { label "Admin Console" }

# Edge
component "gateway" { label "API Gateway" }
component "bff" { label "Mobile BFF" }

# Services
component "orders" { label "Orders" }
component "catalog" { label "Catalog" }
component "payments" { label "Payments" }
component "users" { label "Users" }
component "search" { label "Search" }
component "notify" { label "Notifications" }
component "billing" { label "Billing" }
component "reports" { label "Reports" }

# Shared libraries
component "auth" { label "Auth Lib" }
component "pricing" { label "Pricing Lib" }
component "inventory" { label "Inventory Lib" }
component "events" { label "Event Bus Client" }
component "cache" { label "Cache Client" }
component "templates" { label "Templates" }
component "ledger" { label "Ledger" }
component "index" { label "Search Index" }

# Core
component "db" { label "DB Driver" }
component "http" { label "HTTP Client" }
component "crypto" { label "Crypto" }
component "config" { label "Config" }
component "logging" { label "Logging" }
component "metrics" { label "Metrics" }
component "serde" { label "Serialization" }
component "runtime" { label "Runtime" }

web -> gateway
mobile -> bff
bff -> gateway
cli -> gateway
admin -> gateway
admin -> reports

gateway -> orders
gateway -> catalog
gateway -> users
gateway -> search
gateway -> auth

orders -> payments
orders -> inventory
orders -> pricing
orders -> events
catalog -> inventory
catalog -> pricing
catalog -> cache
payments -> ledger
payments -> crypto
payments -> events
users -> auth
users -> db
search -> index
search -> cache
notify -> templates
notify -> http
billing -> ledger
billing -> pricing
reports -> ledger
reports -> db
events -> notify
events -> billing

auth -> crypto
auth -> config
pricing -> config
inventory -> db
ledger -> db
index -> serde
cache -> serde
templates -> serde

db -> logging
http -> logging
http -> metrics
crypto -> runtime
config -> runtime
logging -> runtime
metrics -> runtime
serde -> runtime
