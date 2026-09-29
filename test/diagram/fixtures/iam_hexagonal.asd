stack {
  layer {
    component "api_client" { label "API Client" }
    actor "browser" { label "Browser / Human" }
  }
  
  layer {
    boundary "iam" {
      label "iam (hexagonal architecture)"
      tint "blue"

      stack {
        layer "driving_adapters" {
          label "Driving Adapters"
          tint "orange"
          component "web" { label "web (HTML UI)" }
          component "service" { label "service (JSON/REST)" }
        }

        stack "core" {
          label "The Core (framework-free)"
          tint "green"
          component "controller" { label "controller (business logic)" }
          layer {
            component "model" { label "model (domain entities)" }
            component "ports" { label "ports (interfaces)" }
          }
        }

        layer "driven_adapters" {
          label "Driven Adapters"
          tint "brown"
          component "kubestore" { label "kubestore" }
          component "kubecrypt" { label "kubecrypt" }
          component "kuberbac" { label "kuberbac" }
          component "system_clock" { label "system" }
          component "memory_store" { label "memorystore" }
          component "memory_rbac" { label "memoryrbac" }
          component "memory_crypto" { label "memorycrypto" }
        }
      }
    }

    boundary "ecp_gateway" {
      label "ecp Gateway (external)"
      tint "orange"
      application "ecp" { label "ecp gateway" }
    }
  }

  layer {
    api "k8s_api" { label "Kubernetes API Server" }
  }
}

browser -> web
api_client -> service

web -> controller
service -> controller
controller -> ports { label "depends only on" }
controller -> model
ports -> model

kubestore -> ports { relation "implements" }
kubecrypt -> ports { relation "implements" }
kuberbac -> ports { relation "implements" }
system_clock -> ports { relation "implements" }
memory_store -> ports { relation "implements" }
memory_rbac -> ports { relation "implements" }
memory_crypto -> ports { relation "implements" }

kubestore -> k8s_api { label "ConfigMaps & Secrets (ADR 0001)" }
kubecrypt -> k8s_api { label "key in Secret (ADR 0005)" }
kuberbac -> k8s_api { label "writes Role CRDs (ADR 0018)" }

ecp -> k8s_api { label "reads Roles, validates JWTs" }
api_client -> ecp { label "PAT (JWT), direct -- iam not in path" }
