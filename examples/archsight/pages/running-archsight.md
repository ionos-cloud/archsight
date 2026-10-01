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
| `archsight analyze` | Run `Analysis` scripts |
| `archsight template [Kind]` | Print a YAML skeleton |
| `archsight diagram <file.asd>` | Render a diagram to SVG |
| `archsight console` | Interactive console |
| `archsight version` | Print the version |

All commands take `-r <dir>` for the resources directory. Useful `web` options: `--port`, `--host`, `--production`, `--disable-reload`, `--inline-edit` (saves edits
straight to the source files) and `--enable-restart` (with `--restart-token`) for `POST /maintenance/restart`.

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
