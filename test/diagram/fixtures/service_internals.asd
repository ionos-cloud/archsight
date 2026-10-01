theme "compact"

layer {
  stack {
    gap "150"
    component "auth_service" { label "Auth Service\nREST API" }
    component "checker_ext" { label "Resource Checker\nGRPC" }
    component "inventory" { label "Inventory\nREST API" }
    component "policy_service" { label "Policy Service\nREST API" }
    component "event_gateway" { label "Event Gateway\nGRPC" }
  }
  
  stack {
    gap "50"
    
    stack {
      gap "50"
      extend "true"
        
      actor "customer" { label "Customer" }
      component "jwt" { label "JWT\nSub: User\nTenant Id" }
    }
  
    group "product_api_server" {
      label "Product API Server"
      tint "blue"

      stack {
        extend "true"
        
        stack {
          no-gap
          component "http_server" { label "HTTP Server"; shape "module" }
          component "metrics_http" { label "Metrics (HTTP)"; shape "module" }
          component "logging" { label "Logging"; shape "module" }
          component "ratelimit" { label "RateLimit"; shape "module" }
          component "authentication" { label "Authentication"; shape "module" }
        }

        group "core" {
          label "Request Pipeline"
          tint "green"
          stack {
            stack {
              no-gap
              component "hooks_modifications" { label "Hooks (modifications)"; shape "module" }
              component "feature_flags" { label "Feature Flags"; shape "module" }
              component "validation_syntax" { label "Validation (syntax)"; shape "module" }
              component "validation_semantic" { label "Validation (semantic)"; shape "module" }
              component "hooks_validations" { label "Hooks (validations)"; shape "module" }
            }

            stack {
              no-gap
              component "authorization" { label "Authorization"; shape "module" }
              component "quota" { label "Quota"; shape "module" }
            }

            stack {
              no-gap
              component "activity_log_publisher" { label "Activity Log Publisher"; shape "module" }
              component "lifecycle_event_publisher" { label "LifeCycle Event Publisher"; shape "module" }
              component "metrics_resource" { label "Metrics (Resource)"; shape "module" }
              component "hooks_before_store" { label "Hooks (before store/post load)"; shape "module" }
            }

            layer {
              component "api_config" { label "Core API\nConfig"; shape "file" }
              component "api_definition" { label "Core API\nDefinition"; shape "file" }
            }
          }
        }

        stack {
          no-gap
          component "resource_checker_health" { label "Resource Checker"; shape "module" }
          component "health" { label "Health"; shape "module" }
          component "metrics_bottom" { label "Metrics"; shape "module" }
          component "http_server_bottom" { label "HTTP Server"; shape "module" }
        }
      }
    }
  }

  stack { 
    gap "100"
    layer {
      stack { 
        gap "100"
        component "loki" { label "Loki" }
        component "feature_flags_ext" { label "Feature Flags\nOpen Feature" }
        component "quota_system" { label "Quota System\nGRPC" }
        component "prometheus" { label "Prometheus" }
      }
    }

    layer {
      database "datastore" { label "DataStore" }
      component "backup_velero" { label "Backup Velero" }
    }

    layer {
      component "api_compiler" { label "API Server Compiler" }
      component "config" { label "Config"; shape "file" }
    }
  }
}

customer -> jwt
jwt -> http_server { label "external API" }

loki -> logging { label "scraped by k8s" }
ratelimit -> feature_flags_ext
feature_flags -> feature_flags_ext
authentication -> auth_service { label "check if token\nstill valid" }
authorization -> policy_service { label "check\npolicy" }
quota -> quota_system { label "create\nreservation" }

validation_semantic -> checker_ext { label "check if resource\nexists" }
checker_ext -> inventory { label "checks" }

activity_log_publisher -> event_gateway
lifecycle_event_publisher -> event_gateway { label "emit" }

core -> datastore { label "store/load" }

backup_velero -> datastore
backup_velero -> config
api_compiler -> config
api_compiler -> api_definition

prometheus -> http_server_bottom { label "scraped" }
