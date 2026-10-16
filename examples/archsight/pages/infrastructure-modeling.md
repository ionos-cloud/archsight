---
title: Infrastructure Modeling
tags: howto, modeling, infrastructure
status: approved
toc: yes
---

# Infrastructure Modeling

A walk through the infrastructure of the example model: where things are, what is physical, which networks run
over it and what runs on them. The rules behind it are in "Choosing the Kind: Infrastructure" of
[Architecture Modeling](/doc/modeling).

```asd
layer "where" {
  label "Where"
  component "metro" { label "Frankfurt metro"; resource "Location/Location:Germany:Frankfurt" }
  component "campus" { label "Frankfurt campus"; resource "TechnologyFacility/Facility:Frankfurt:Campus" }
  component "madrid" { label "Madrid DC"; resource "TechnologyFacility/Facility:Madrid:DC" }
}
layer "physical" {
  label "Physical"
  component "link" { label "Link Frankfurt-Madrid"; resource "TechnologyEquipment/Equipment:Link:Frankfurt-Madrid"; shape "pipe" }
  component "backbone" { label "Backbone"; resource "TechnologyEquipment/Equipment:Backbone" }
}
layer "network" {
  label "Networks"
  component "underlay" { label "Underlay"; resource "TechnologyCommunicationNetwork/Network:Underlay:Frankfurt-Madrid" }
  component "evpn" { label "EVPN overlay"; resource "TechnologyCommunicationNetwork/Network:Overlay:EVPN" }
  component "mgmt" { label "Management Frankfurt"; resource "TechnologyCommunicationNetwork/Network:Management:Frankfurt" }
}
layer "compute" {
  label "Compute"
  component "web01" { label "Web01"; resource "TechnologyNode/Node:Frankfurt:Web01" }
  component "routing" { label "EVPN routing"; resource "TechnologySystemSoftware/Tech:Routing:EVPN" }
}
campus -> metro { label "locatedAt" }
link -> campus { label "locatedAt" }
link -> madrid { label "locatedAt" }
backbone -> link { label "composedOf" }
evpn -> underlay { label "servedBy" }
evpn -> routing { label "realizedBy" }
web01 -> mgmt { label "servedBy" }
web01 -> campus { label "locatedAt (hall A)" }
```

## Where: locations and facilities

[[Location/Location:Germany:Frankfurt]] is the metro area, [[TechnologyFacility/Facility:Frankfurt:Campus]] the campus in it.
The campus is `composedOf` its halls, so only the campus needs a location. [[TechnologyFacility/Facility:Madrid:DC]] is a
colocation site in [[Location/Location:Spain:Madrid]].

## Physical: equipment and links

A rack such as [[TechnologyEquipment/Equipment:Frankfurt:HallA:Rack01]] is `locatedAt` its hall. The fibre route
[[TechnologyEquipment/Equipment:Link:Frankfurt-Madrid]] is one link `locatedAt` both of its ends, and
[[TechnologyEquipment/Equipment:Backbone]] is `composedOf` the links. The logical backbone service
[[TechnologyService/Network:Backbone]] is `realizedBy` it.

## Devices and rooms

Hall A is `composedOf` two rooms, [[TechnologyFacility/Facility:Frankfurt:HallA:Room1]] and
[[TechnologyFacility/Facility:Frankfurt:HallA:Room2]] (`facility/type: room`), each a fire compartment. Every physical
machine is a `TechnologyDevice` `locatedAt` its room, so the room page lists what is lost with it.

- The servers are cabled to the core switch member of their room (`connectedTo`, declared once per cable).
- The core switch [[TechnologyDevice/Device:Frankfurt:Switch:Core]] is one virtual chassis `composedOf` its members
  n0 and n1, one per room. [[TechnologyCommunicationNetwork/Network:Management:Frankfurt]] is `realizedBy` the chassis
  and `connects` the servers and firewalls; the underlay is `realizedBy` the two core routers.
- The logical node [[TechnologyNode/Node:Frankfurt:Hypervisors]] is `realizedBy` the four servers, and the rack
  [[TechnologyEquipment/Equipment:Frankfurt:HallA:Rack01]] is `composedOf` the two it holds.

![Hall A, room by room](site-rooms.asd)

## Networks

- [[TechnologyCommunicationNetwork/Network:Underlay:Frankfurt-Madrid]] is the routed underlay between the sites.
- [[TechnologyCommunicationNetwork/Network:Overlay:EVPN]] is the overlay that carries private workloads: one network, not one
  per customer. It is `servedBy` the underlay and `realizedBy` the routing software [[TechnologySystemSoftware/Tech:Routing:EVPN]].
- [[TechnologyCommunicationNetwork/Network:Overlay:Tenant]] is built by software: it is `realizedBy` the
  [[ApplicationComponent/Network:Operator]] that creates the VXLAN segments and the [[ApplicationComponent/Network:SDNAgent]]
  on every host, not by the system software of the nodes it serves.
- [[TechnologyCommunicationNetwork/Network:Management]] is the concept; [[TechnologyCommunicationNetwork/Network:Management:Frankfurt]]
  `specializes` it for one site.
- [[TechnologyCommunicationNetwork/Network:VPN:Office]] tunnels through [[TechnologyCommunicationNetwork/Network:Public]].
- [[TechnologyCommunicationNetwork/Network:Metro:Frankfurt]] supports the metro region: `locatedAt` the location and
  `composedOf` the site networks.

```view
apiVersion: architecture/v1alpha1
kind: View
metadata:
  name: All networks
  annotations:
    view/query: 'TechnologyCommunicationNetwork: name =~ "Network"'
    view/fields: name, network/type, network/topology
    view/sort: name
```

## Compute

[[TechnologyNode/Node:Frankfurt:Web01]] stands in hall A (`locatedAt`) and is attached to the Frankfurt management
network (`servedBy`). [[TechnologySystemSoftware/Tech:Puma:Cluster]] is one cluster `locatedAt` three facilities,
not three copies.

```view
apiVersion: architecture/v1alpha1
kind: View
metadata:
  name: Everything in the Madrid data center
  annotations:
    view/query: '-> "Facility:Madrid:DC" & ! kind == "Page"'
    view/fields: name, kind
```

## Checks

`archsight lint` warns (section "Modeling warnings") about a link that is not located at two facilities, an overlay
or VPN that no network serves, a top-level facility without a location and equipment that is placed nowhere.
