boundary "internet" {
  label "Internet"
  actor "user" { label "User" }
}

stack "tiers" {
  label "Tiers"

  boundary "dmz" {
    label "DMZ"
    tint "orange"

    layer "edge" {
      label "Edge APIs"
      tint "orange"
      api "web_api" { label "Web API" }
      api "mobile_api" { label "Mobile API" }
    }
  }

  layer "app_tier" {
    label "Application Tier"
    tint "blue"
    application "order_service" { label "Order Service" }
    application "payment_service" { label "Payment Service" }
  }

  layer "backing_services" {
    label "Backing Services"
    tint "purple"

    stack "db_host" {
      label "Database Host"
      tint "brown"
      component "os" { label "Linux" }
      component "runtime" { label "Postgres Runtime" }
      database "orders_db" { label "Orders DB" }
    }

    queue "event_bus" { label "Order Events" }
  }
}

boundary "payment_provider" {
  label "External Payment Provider"
  tint "orange"
  component "payment_gateway" { label "Payment Gateway" }
}

user -> web_api
user -> mobile_api
web_api -- mobile_api { label "shared gateway" }

web_api -> order_service
mobile_api -> order_service
order_service -> payment_service

payment_service -> payment_gateway { relation "implements" }

order_service -> orders_db { relation "data" }
order_service -> event_bus { relation "control" }
order_service <-> event_bus { relation "data"; label "publish/consume" }
