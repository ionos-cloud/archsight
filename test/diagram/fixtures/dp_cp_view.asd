# Data Plane / Control Plane view: how each architecture layer's control
# plane is deployed onto the data plane of the layer below it, down to the
# Undercloud/Regional Cluster. Recreated from the internal "dp-cp-view"
# drawio diagram.

stack {
  gap "20"

  actor "customer" { label "Customer" }

  layer {
    boundary "SaaS" {
      tint "gray"
      extend "height"

      stack {
        gap "30"
        api "saas_api" { label "API"; tint "red" }

        group "saas_cp_container" {
          label "**Container@Mk8s**"
          tint "purple"
          component "saas_cp" { label "Control Plane"; tint "purple" }
        }
      }
    }

    boundary "PaaS" {
      tint "gray"
      extend "height"

      stack {
        gap "30"
        api "paas_api" { label "API"; tint "red" }

        group "paas_cp_vm" {
          label "**VM@IC**"
          tint "yellow"
          component "paas_cp" { label "Control Plane"; tint "yellow" }
        }

        component "saas_dp" { label "**Data Plane**\nContainer@Mk8s"; tint "purple" }
      }
    }

    boundary "IaaS" {
      tint "gray"
      extend "height"

      stack {
        gap "30"
        api "iaas_api" { label "API"; tint "red" }

        group "iaas_cp_vm" {
          label "**VM@SlimStack**"
          tint "blue"
          component "iaas_cp" { label "Control Plane"; tint "blue" }
        }

        component "paas_dp" { label "**Data Plane**\nVM@IC"; tint "yellow" }
      }
    }

    boundary "undercloud" {
      label "Undercloud / Regional Cluster"
      tint "gray"
      extend "height"

      stack {
        gap "30"
        stack "slimstack" {
          label "**Slim Stack**"
          tint "gray"
          component "slim_cp" { label "Control Plane@k8s" }
          component "slim_dp" { label "Data Plane@VM@k8s"; tint "blue" }
        }

        component "iaas_dp" { label "**Data Plane**\nphysical@IC"; tint "blue" }
      }
    }
  }
}

# Customer calls into each layer's own API.
customer -> saas_api { label "use"; tint "red" }
customer -> paas_api { label "use";  tint "red" }
customer -> iaas_api { label "use";  tint "red" }

saas_api -> saas_cp
paas_api -> paas_cp
iaas_api -> iaas_cp

# Each layer's control plane calls into the API of the layer immediately
# below it, and each layer's own hosting substrate (the group wrapping its
# control plane) runs on the data plane of the layer immediately below.
saas_cp -> paas_api
paas_cp -> iaas_api
iaas_cp -> iaas_dp { label "manage";  tint "red" }

saas_cp_container -> paas_dp
paas_cp_vm -> iaas_dp
iaas_cp_vm -> slim_dp


saas_cp -> paas_cp { label "allowed dependency"; tint "green" }

paas_cp -> iaas_cp { label "allowed dependency"; tint "green" }
saas_cp -> iaas_cp { label "allowed dependency"; tint "green" }

iaas_cp -> slim_cp { label "allowed dependency"; tint "green" }
saas_cp -> slim_cp { label "allowed dependency"; tint "green" }
paas_cp -> slim_cp { label "allowed dependency"; tint "green" }
