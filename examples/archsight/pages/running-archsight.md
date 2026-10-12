---
title: Running Archsight
tags: howto, operations
author: Vincent Landgraf <vincent.landgraf@ionos.com>
owner: Vincent Landgraf <vincent.landgraf@ionos.com>
status: approved
toc: yes
---

# Running Archsight

## Commands

| Command | Purpose |
|---------|---------|
| `archsight web` | Web UI, REST API and MCP server |
| `archsight lint` | Validate resources, links, pages and diagrams (non-zero exit on errors) |
| `archsight import` | Run imports, see [[Importing Data]] |
| `archsight analyze` | Run `Analysis` scripts; `--format typst` writes a [Typst](https://typst.app) report |
| `archsight template [Kind]` | Print a YAML skeleton |
| `archsight diagram <file.asd>` | Render a diagram to SVG |
| `archsight console` | Interactive console |
| `archsight version` | Print the version |

All commands take `-r <dir>` for the resources directory. Useful `web` options: `--port`, `--host`, `--production`, `--disable-reload`, `--inline-edit` (saves edits
straight to the source files) and `--enable-restart` (with `--restart-token`) for `POST /maintenance/restart`.

## Analysis reports

`archsight analyze` prints the result of every analysis in the terminal. `--format typst` writes the same results as one
[Typst](https://typst.app) document, for a report you can hand around:

```bash
archsight analyze -r resources --format typst -o report.typ
archsight analyze -r resources -f 'Component' --format typst > report.typ
typst compile report.typ
```

The document has a summary and a section per analysis with its tables, lists, text and messages. Code sections written
in the diagram language (`asd`) become inline diagrams. Without `-o` the source goes to stdout, so you can also paste it
into typst.app. Terminal and report both cut tables and lists after 10 rows, `-v` keeps them all.

## Docker

```bash
docker run -p 4567:4567 -v "$PWD/resources:/resources" ghcr.io/ionos-cloud/archsight
```

Details in [Docker](/doc/docker).

## Kubernetes

The Helm chart supports resources from a ConfigMap, a git-sync sidecar or a volume:

```bash
helm install archsight oci://ghcr.io/ionos-cloud/archsight/charts/archsight
```

Details in [Kubernetes](/doc/kubernetes).

## Recommended pipeline

1. CI runs `archsight lint` on every merge request to the architecture repository.
2. A scheduled job runs `archsight import` and commits the generated YAML.
3. The deployment picks up the new content, either by restarting or by the reload endpoint.

A broken link, a page in no menu or an unknown diagram resource then fails the pipeline instead of the
reader's browser.
