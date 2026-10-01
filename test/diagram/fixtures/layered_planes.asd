# Layered tiers with nested boundaries: the control plane of each tier is
# hosted on the data plane of the tier below it, down to the base cluster.


stack {
  gap "20"

  actor "consumer" { label "Consumer" }

  layer {
    boundary "Tier A" {
      tint "gray"
      extend "height"

      stack {
        gap "30"
        api "api_a" { label "API"; tint "red" }

        group "host_a" {
          label "**Container@Pool**"
          tint "purple"
          component "cp_a" { label "Control Plane"; tint "purple" }
        }
      }
    }

    boundary "Tier B" {
      tint "gray"
      extend "height"

      stack {
        gap "30"
        api "api_b" { label "API"; tint "red" }

        group "host_b" {
          label "**VM@Site**"
          tint "yellow"
          component "cp_b" { label "Control Plane"; tint "yellow" }
        }

        component "dp_a" { label "**Data Plane**\nContainer@Pool"; tint "purple" }
      }
    }

    boundary "Tier C" {
      tint "gray"
      extend "height"

      stack {
        gap "30"
        api "api_c" { label "API"; tint "red" }

        group "host_c" {
          label "**VM@Platform**"
          tint "blue"
          component "cp_c" { label "Control Plane"; tint "blue" }
        }

        component "dp_b" { label "**Data Plane**\nVM@Site"; tint "yellow" }
      }
    }

    boundary "base" {
      label "Base / Regional Cluster"
      tint "gray"
      extend "height"

      stack {
        gap "30"
        stack "basestack" {
          label "**Base Stack**"
          tint "gray"
          component "cp_base" { label "Control Plane@k8s" }
          component "dp_base" { label "Data Plane@VM@k8s"; tint "blue" }
        }

        component "dp_c" { label "**Data Plane**\nphysical@Site"; tint "blue" }
      }
    }
  }
}

# The consumer calls the API of every tier.
consumer -> api_a { label "use"; tint "red" }
consumer -> api_b { label "use";  tint "red" }
consumer -> api_c { label "use";  tint "red" }

api_a -> cp_a
api_b -> cp_b
api_c -> cp_c

# The control plane of a tier calls the API of the tier below it, and the host
# that runs it (the group around it) sits on the data plane of the tier below.
cp_a -> api_b
cp_b -> api_c
cp_c -> dp_c { label "manage";  tint "red" }

host_a -> dp_b
host_b -> dp_c
host_c -> dp_base


cp_a -> cp_b { label "allowed dependency"; tint "green" }

cp_b -> cp_c { label "allowed dependency"; tint "green" }
cp_a -> cp_c { label "allowed dependency"; tint "green" }

cp_c -> cp_base { label "allowed dependency"; tint "green" }
cp_a -> cp_base { label "allowed dependency"; tint "green" }
cp_b -> cp_base { label "allowed dependency"; tint "green" }
