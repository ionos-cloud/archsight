# A web shop on one host: clients connect to the gateway's ports, the gateway hands work to its workers
theme "cozy"
badge "beta" { tint "orange"; label "beta only" }
line "dashed" { label "read only at start" }
stack {
  component "browser" { label "**browser**"; no-extend; align "api" }
  boundary "host" {
    label "One host"
    stack {
      layer {
        anchor "right"
        component "mobile" { label "**mobile app**"; badge "beta" }
        component "cli" { label "**cli**" }
        file "conf" { label "`gateway.conf`" }
      }
      component "gateway" {
        label "**gateway**\nterminates TLS, routes each request"
        tint "teal"
        port "https" { label "tcp :443"; side "top" }
        port "grpc" { label "unix grpc.sock"; side "top"; badge "beta" }
      }
      layer {
        stack {
          component "api" {
            label "**api**\nanswers requests"
            no-extend
            anchor "right"
            port "http" { label ":8080"; side "top" }
            port "out" { label ":9090"; side "bottom"; at "left" }
          }
          database "db" { label "`orders.db`" }
        }
        stack {
          file "queue_file" { label "`jobs.sqlite`"; no-extend; anchor "left" }
          component "worker" {
            label "**worker**\nruns the jobs it polls, one at a time"
            port "status" { label "status"; side "top"; at "right" }
          }
        }
        boundary "kernel" {
          label "KERNEL"
          tint "purple"
          layer {
            component "routes" { label "route table"; tint "purple"; align "worker" }
            component "nft" { label "`nftables`"; tint "purple" }
          }
        }
      }
    }
  }
}
browser -> gateway.https { label "HTTPS" }
mobile -> gateway.grpc { label "gRPC" }
cli -> gateway.grpc { label "gRPC" }
conf -> gateway { label "read at start"; line "dashed" }
gateway -> api.http { label "`proxy_pass`" }
api.out -> db { label "SQL" }
gateway -> queue_file { label "jobs" }
queue_file -> worker { label "polls" }
worker.status -> gateway { label "status" }
worker -> routes { label "netlink" }
gateway -> nft { label "libnftables" }
