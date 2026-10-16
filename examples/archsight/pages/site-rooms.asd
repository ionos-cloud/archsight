# Hall A in Frankfurt, room by room: the hosts of each room hang off the core switch member that stands in the same
# room; the two members form one virtual chassis, and each core router is cabled to both members. Every box links to
# its TechnologyDevice, so the picture can be checked against the model.

theme "cozy"
legend "none"

layer "hall" {
  label "**Hall A** (Frankfurt)"
  resource "TechnologyFacility/Facility:Frankfurt:HallA"

  stack "room1" {
    label "**Room 1**"
    resource "TechnologyFacility/Facility:Frankfurt:HallA:Room1"
    gap "40"
    layer "room1_net" {
      label "Network"
      component "router01" { label "Router01\ncore router"; tint "teal"; resource "TechnologyDevice/Device:Frankfurt:Router01" }
      component "n0" { label "n0\ncore switch"; tint "indigo"; resource "TechnologyDevice/Device:Frankfurt:Switch:Core:n0" }
    }
    layer "room1_hosts" {
      label "Hosts"
      component "server01" { label "Server01"; resource "TechnologyDevice/Device:Frankfurt:Server01" }
      component "server02" { label "Server02"; resource "TechnologyDevice/Device:Frankfurt:Server02" }
      component "storage01" { label "Storage01"; resource "TechnologyDevice/Device:Frankfurt:Storage01" }
      component "firewall01" { label "Firewall01"; tint "red"; resource "TechnologyDevice/Device:Frankfurt:Firewall01" }
    }
  }

  stack "room2" {
    label "**Room 2**"
    resource "TechnologyFacility/Facility:Frankfurt:HallA:Room2"
    gap "40"
    layer "room2_net" {
      label "Network"
      component "n1" { label "n1\ncore switch"; tint "indigo"; resource "TechnologyDevice/Device:Frankfurt:Switch:Core:n1" }
      component "router02" { label "Router02\ncore router"; tint "teal"; resource "TechnologyDevice/Device:Frankfurt:Router02" }
    }
    layer "room2_hosts" {
      label "Hosts"
      component "server03" { label "Server03"; resource "TechnologyDevice/Device:Frankfurt:Server03" }
      component "server04" { label "Server04"; resource "TechnologyDevice/Device:Frankfurt:Server04" }
      component "storage02" { label "Storage02"; resource "TechnologyDevice/Device:Frankfurt:Storage02" }
      component "firewall02" { label "Firewall02"; tint "red"; resource "TechnologyDevice/Device:Frankfurt:Firewall02" }
    }
  }
}

room1_hosts -- n0 { style "orthogonal" }
room2_hosts -- n1 { style "orthogonal" }
n0 -- n1 { label "chassis link" }
router01 -- n0
router01 -- n1
router02 -- n0
router02 -- n1
router01 -- router02
