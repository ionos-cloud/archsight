---
title: Searching and Queries
tags: howto, query
author: Vincent Landgraf <vincent.landgraf@ionos.com>
owner: Vincent Landgraf <vincent.landgraf@ionos.com>
status: approved
toc: yes
---

# Searching and Queries

The search box, `View` resources, the REST API and the MCP `query` tool all speak the same language.
Reference: [Query Syntax](/doc/search).

## Shape of a query

```text
[Kind:] condition [& | condition ...]
```

| I want | Query |
|--------|-------|
| everything named like a word | `kubernetes` |
| all of one kind | `TechnologyArtifact:` |
| filter by annotation | `activity/status == "active"` |
| annotation is missing | `! activity/status?` |
| numeric comparison | `scc/language/Go/loc > 10000` |
| has a relation to a kind | `-> ApplicationInterface` |
| reaches something transitively | `ApplicationComponent: ~> BusinessRequirement` |
| only follow one verb | `TechnologyArtifact: -{maintainedBy}> "Team:Platform"` |
| orphans | `-> none & <- none` |
| wiki pages by tag | `Page: page/tags == "concept"` |

## Recipes

Unmaintained repositories that are still active:

```text
TechnologyArtifact: activity/status == "active" & -{maintainedBy}> none
```

Everything that ends up serving a compliance requirement:

```text
~{realizedThrough,servedBy}> BusinessRequirement
```

Sub-queries let you ask about the target instead of naming it:

```text
TechnologyArtifact: -{maintainedBy}> $(BusinessActor: activity/status == "active")
```

## Views

A `View` saves a query with columns and sort order, and appears in the sidebar.

```yaml
kind: View
metadata:
  name: ActiveContainers
  annotations:
    view/query: 'TechnologyArtifact: activity/status == "active" & repository/artifacts == "container"'
    view/fields: activity/status,repository/artifacts
    view/sort: -name
```
