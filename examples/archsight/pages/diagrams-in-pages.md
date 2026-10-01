---
title: Diagrams in Pages
tags: howto, diagram
author: Vincent Landgraf <vincent.landgraf@ionos.com>
owner: Vincent Landgraf <vincent.landgraf@ionos.com>
status: approved
toc: yes
---

# Diagrams in Pages

Diagrams are text in `asd` fenced blocks. They render to inline SVG, need no external tool and live in
review-friendly diffs. Full reference: [Diagrams](/doc/diagram).

## Basics

````markdown
```asd
group "vpc" {
  label "Production"
  component "api" { label "API" }
  database "db" { label "Postgres" }
}
actor "client" { label "Client" }
client -> api
api -> db { label "reads/writes" }
```
````

```asd
group "vpc" {
  label "Production"
  component "api" { label "API" }
  database "db" { label "Postgres" }
}
actor "client" { label "Client" }
client -> api
api -> db { label "reads/writes" }
```

## Link nodes to the model

`resource "Name"` (or `Kind/Name`) turns a node into a link and takes its icon and kind from the resource.
Unknown names render dashed and are reported by `archsight lint`, so diagrams cannot silently rot.

```asd
component "engine" { label "Query engine"; resource "Archsight:Query:Engine" }
component "db" { label "Database"; resource "Archsight:Core:Database" }
engine -> db
```

## Diagram as annotation

Put the source in the `architecture/diagram` annotation of any resource and it is shown on the resource
page next to the generated dependency graph. Use it for the hand-drawn overview, keep pages for the story.

## Command line

```bash
bundle exec archsight diagram my.asd -o my.svg
```
