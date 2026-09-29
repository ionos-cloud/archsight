stack {
  actor "client" { label "Client" }

  boundary "vpc" {
    label "Production VPC"

    stack {
      group "public" {
        label "Public Subnet"
        tint "orange"
        component "lb" { label "Load Balancer" }
      }

      group "private" {
        label "Private Subnet"
        tint "green"
        api "api_service" { label "API Service" }
        database "db" { label "Postgres" }
      }
    }
  }
}

client -> lb
lb -> api_service
api_service -> db { style "orthogonal"; label "reads/writes" }
