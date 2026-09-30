---
title: Importing Data
tags: howto, import
author: Vincent Landgraf <vincent.landgraf@ionos.com>
owner: Vincent Landgraf <vincent.landgraf@ionos.com>
status: approved
toc: yes
---

# Importing Data

Repositories, teams and code metrics change too often to type by hand. `Import` resources describe where
to fetch them and Archsight writes the resulting YAML into the resources directory. Reference:
[Import System](/doc/import).

## Flow

```asd
layer "flow" {
  label "Import flow"
  component "import" { label "**Import**\nresource" }
  component "handler" { label "**Handler**\n(GitHub, GitLab, git, REST)" }
  component "yaml" { label "**Generated**\nYAML" }
  component "db" { label "Database"; resource "Archsight:Core:Database" }
}
import -> handler { label "configures" }
handler -> yaml { label "writes" }
yaml -> db { label "loaded on reload" }
```

## Run

```bash
archsight import --dry-run   # show the plan
archsight import             # run what is out of date
archsight import --force     # ignore caches
```

## Rules of thumb

- Generated output lives in its own folder (`generated/` in the example) and is never edited by hand.
- Use `import/cacheTime` so a daily run does not re-clone everything.
- A parent import can `generate` child imports, dependencies are derived and children run afterwards.
- Hand-written resources reference generated ones by name, so a failed import breaks lint loudly instead of
  silently dropping relations.
- Licenses and dependencies are analysed during import: see [License Scanning](/doc/licenses).
