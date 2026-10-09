---
title: Language Strategy
tags: concept, decision
author: Vincent Landgraf <vincent.landgraf@ionos.com>
owner: Vincent Landgraf <vincent.landgraf@ionos.com>
status: approved
toc: yes
links:
  confluence: https://confluence.example.com/spaces/ARCH/pages/12345/Language+Strategy
---

# Language Strategy

Which languages Archsight is written in, and where a new language is allowed to appear.

## Current state

| Language | Where | Why |
|----------|-------|-----|
| Ruby (>= 3.4) | Everything server side: database, query engine, linter, CLI, importers, Sinatra API, MCP server, diagram layout | Fast to change, good fit for DSLs (query language, `.asd`, resource classes), one runtime to deploy |
| Vue 3 + JavaScript | Web UI in `frontend/`, built with Vite | Small SPA on top of the REST API, no TypeScript so far |
| C | Optional native kernels for the diagram edge-routing hot loops | Only speeds up routing of congested diagrams, a pure Ruby fallback always exists |
| YAML + Markdown | The model and the handbook | Reviewable in git, editable without the tool |
| RBS | Type signatures in `sig/`, checked by Steep | Types where they help, without leaving Ruby |

Ruby is about 49k lines of the code base, Vue about 7k, C below 1k.

## Decisions

- **Ruby first.** New backend features are Ruby. A second server-side language would split the deployment
  into two runtimes and the contributors into two groups.
- **Native code must be optional.** Any C extension needs a Ruby fallback with the same output, and
  `rake test` compiles the extension first.
- **Frontend stays thin.** Logic that the CLI, the API and the MCP server also need belongs in Ruby.
  The UI renders what the API returns.
- **Analyzed languages are not implementation languages.** The importers understand Go, Ruby, Python,
  Rust, Java, JavaScript, C++, Elixir and Crystal repositories to build module graphs, but only to describe
  *other* systems.

## How the pieces fit

```asd
layer "stack" {
  label "Implementation languages"
  component "ruby" { label "**Ruby**\nserver, CLI, importers" }
  component "vue" { label "**Vue 3**\nweb UI" }
  component "c" { label "**C**\noptional routing kernels" }
}
vue -> ruby { label "REST API" }
ruby -> c { label "optional" }
```

## Revisit when

- The UI needs more than a few thousand lines of state handling: consider TypeScript.
- Diagram routing needs more than the current kernels: prefer extending the C kernels over
  a new language.
- Importing large repositories becomes the bottleneck: a separate analyzer process would be the first
  place a second language could be justified, see [[Importing Data]].
