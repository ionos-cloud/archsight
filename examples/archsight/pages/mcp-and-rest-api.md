---
title: MCP and REST API
tags: howto, api, mcp
author: Vincent Landgraf <vincent.landgraf@ionos.com>
owner: Vincent Landgraf <vincent.landgraf@ionos.com>
status: approved
toc: yes
---

# MCP and REST API

## REST API

Everything the UI shows comes from `/api/v1`, the OpenAPI document is served by the app. See
[REST API Documentation](/docs/api). Typical endpoints:

| Endpoint | Returns |
|----------|---------|
| `GET /api/v1/kinds` | Kinds with instance counts |
| `GET /api/v1/kinds/{kind}/instances/{name}` | One resource with relations |
| `GET /api/v1/search?q=...` | Instances matching a query, see [[Searching and Queries]] |
| `GET /api/v1/pages` | The page tree, unsorted pages included |
| `GET /api/v1/pages/:name` | One page with breadcrumb and table of contents |

## MCP server

`archsight web` also serves MCP at `/mcp`, so assistants can work on the real model instead of
guessing. It exposes four tools:

| Tool | Use |
|------|-----|
| `resource_doc` | List kinds, or show annotations, relations and a template for one kind |
| `query` | Run a query and return matching resources |
| `analyze_resource` | Explain one resource with its relations |
| `execute_analysis` | List or run `Analysis` resources |

Example prompt: *"Which active repositories have no maintaining team? Use the query tool."*

## Analyses

An `Analysis` resource holds a Ruby script that runs in a sandbox against the loaded database. Use it for
questions a query cannot express, such as scoring or cross-checks. Run with `archsight analyze` or through
the MCP `execute_analysis` tool. An example is in `examples/archsight/analyses/sample.yaml`.
