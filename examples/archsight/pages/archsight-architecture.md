---
title: Archsight Architecture
tags: concept, architecture
author: Vincent Landgraf <vincent.landgraf@ionos.com>
owner: Vincent Landgraf <vincent.landgraf@ionos.com>
status: approved
toc: yes
---

# Archsight Architecture

Archsight is modelled in Archsight. The components below are real resources in this example, click through
to see their relations. The diagram is a plain `.asd` file next to this page, embedded like an image.

![Archsight components](archsight-overview.asd)

## Components and deployment

A draw.io diagram with two pages, shown by the draw.io viewer that Archsight serves itself. Use the page selector in its toolbar for the second page:

![Archsight components and deployment](archsight-components.drawio)

## Building blocks

| Block | Responsibility |
|-------|----------------|
| [[ApplicationComponent/Archsight:Core:Resources]] | Resource kinds, annotations, relation verbs |
| [[ApplicationComponent/Archsight:Core:Database]] | Loads YAML and pages, validates, resolves relations, computes annotations |
| [[ApplicationComponent/Archsight:Query:Engine]] | Lexer, parser and evaluator of the query language |
| [[ApplicationComponent/Archsight:Web:API]] | Sinatra REST API with OpenAPI spec |
| [[ApplicationComponent/Archsight:Web:Frontend]] | Vue 3 single page app |
| [[ApplicationComponent/Archsight:Query:MCP]] | MCP server for AI assistants |
| [[ApplicationComponent/Archsight:Render:GraphViz]] | DOT generation, rendered client side via WASM |
| [[ApplicationComponent/Archsight:Render:Diagram]] | `.asd` to SVG with layout and routing, optional native kernels |
| [[ApplicationComponent/Archsight:Util:Linter]] | Model validation |
| [[ApplicationComponent/Archsight:CLI:Commands]] | Thor commands |

## Design decisions

- **Files are the database.** Everything is loaded into memory on start and on reload. This keeps review,
  history and rollback in git and makes the tool trivial to deploy.
- **One loader for everyone.** UI, linter, API and MCP share `Database`, so there is no second source of truth.
- **Server-side rendering of diagrams**, client-side rendering of graphs. Diagrams must be identical in the
  UI, in exports and on the command line; graphs are interactive and cheap.
- **Optional native code.** The diagram kernels have a pure Ruby fallback, the C extension only speeds up
  congested diagrams.

Technology stack and directory layout: [Architecture](/doc/architecture).
