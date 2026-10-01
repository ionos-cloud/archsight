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
| `GET /api/v1/pages` | The page tree (unsorted pages included), page tags and the home page |
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

### Pages over MCP

There is no page tool: `Page` and `PageMenu` are resources like any other, and the server is read-only.

| I want | Tool call |
|--------|-----------|
| how many pages, which names | `query` with `Page:` and `output: "count"` or `"brief"` |
| pages by tag or status | `query` with `Page: page/tags == "howto"` |
| pages that mention a word | `query` with `Page: page/content =~ "asd"` |
| one page (metadata and markdown) | `analyze_resource` with `kind: "Page"`, `name: "<page name>"` |
| the root menus, a menu's contents | `query` with `PageMenu: <- none`, `analyze_resource` with `kind: "PageMenu"` |

A bare word matches names only, so full-text search always uses `page/content`. Keep `limit` small when you ask
for `complete` output: it returns the whole markdown of every match. Details and more queries are in
[Wiki Pages](/doc/pages#pages-and-ai-assistants-mcp) and the [Query Syntax](/doc/search#searching-wiki-pages).

## Analyses

An `Analysis` resource holds a Ruby script that runs in a sandbox against the loaded database. Use it for
questions a query cannot express, such as scoring or cross-checks. Run with `archsight analyze` or through
the MCP `execute_analysis` tool. An example is in `examples/archsight/analyses/sample.yaml`.
