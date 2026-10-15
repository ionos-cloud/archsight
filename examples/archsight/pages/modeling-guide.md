---
title: Modeling Guide
tags: howto, modeling
author: Vincent Landgraf <vincent.landgraf@ionos.com>
owner: Vincent Landgraf <vincent.landgraf@ionos.com>
status: approved
toc: yes
---

# Modeling Guide

The full reference is [Architecture Modeling](/doc/modeling). This page is the short version and the rules we
apply to Archsight's own model.

## Pick a direction

- **Bottom-up** if you already have repositories: import them ([[Importing Data]]), group them into
  components, expose interfaces, then attach teams.
- **Top-down** for new work: stakeholder, goal, requirement, capability, service, component.

Most models start bottom-up and grow a thin top-down layer of capabilities and requirements later.

## The realization chain

```asd
component "req" { label "MotivationRequirement" }
component "svc" { label "ApplicationService" }
component "comp" { label "ApplicationComponent" }
component "art" { label "TechnologyArtifact" }
req -> svc { relation "implements" }
svc -> comp { relation "implements" }
comp -> art { relation "implements" }
```

## Naming

- Use `Product:Area:Thing` style names (`Archsight:Query:Engine`), colons group related resources in lists.
- Repositories are `Repo:<org>:<name>`, interfaces `Public:<Product>:<version>:<Name>`.
- Never rename a resource without searching for incoming relations first: `<- "OldName"`.

## Checklist for a new component

1. `architecture/description` in one or two sentences, saying what it does, not what it is built with.
2. `realizedThrough` at least one `TechnologyArtifact`.
3. `exposes` every interface others rely on, `dependsOn` the ones it consumes.
4. A maintaining `BusinessActor` (usually inherited from the artifact via import).
5. `archsight lint` passes.

## Keeping the model honest

- Mark retired things with `activity/status: abandoned` instead of deleting, so history stays queryable.
- Mark products, components and services that are on their way out with `lifecycle/status`, see
  [Lifecycle](#lifecycle).
- Use a [[Searching and Queries|query]] as a health check, for example unowned artifacts:
  `TechnologyArtifact: -{maintainedBy}> none`.
- Save such checks as `View` resources so they show up in the sidebar.
- Write checks that need logic as an `Analysis`. This one lists components that nothing refers to, and it runs
  every time this page opens:

![[Analysis/Analysis:Component:Relations]]

## Lifecycle

Every resource that carries `architecture/*` annotations can say where it is in its life with `lifecycle/status`:

| Status | Meaning |
|--------|---------|
| `planned` | Not yet in use: decided or being built, `lifecycle/activeAt` says when it starts |
| `active` | In use, no restriction (the default: a resource without the annotation is `active`) |
| `deprecated` | Still works, but do not start new uses |
| `sunset` | Being phased out, there is a date after which it goes away |
| `end-of-life` | No longer operated or supported |

The status is shown as a coloured badge, blue for `planned`, yellow for `deprecated`, red for `sunset` and
`end-of-life`. Companions record the story: `lifecycle/activeAt`, `lifecycle/deprecatedAt`, `lifecycle/sunsetAt` and `lifecycle/endOfLifeAt` (ISO 8601 dates),
`lifecycle/replacedBy` (the replacing resource, a name for the same kind or `Kind/Name` for another kind such as a component replaced by a service; shown as a link, `archsight lint` checks that it exists) and
`lifecycle/reason`.

```yaml
metadata:
  name: Billing:Legacy:Export
  annotations:
    lifecycle/status: sunset
    lifecycle/sunsetAt: 2027-03-31
    lifecycle/replacedBy: ApplicationService/Billing:Export:v2
    lifecycle/reason: The v2 export covers all formats.
```

Find them with the query `lifecycle/status == "deprecated"` or the sidebar filter. This view lists all of them:

![[View/View:Lifecycle]]

The analysis also shows what still depends on each:

![[Analysis/Analysis:Lifecycle:Dependents]]
