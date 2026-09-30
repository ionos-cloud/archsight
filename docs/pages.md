# Wiki Pages

Pages are markdown files with YAML frontmatter. They are loaded as `Page` resources and arranged in the
sidebar (above the Kinds) by `PageMenu` resources.

## Page file

```markdown
---
title: Language Strategy
tags: concept, ga, requirement
author: John Smith <john.smith@example.com>
owner: John Smith <john.smith@example.com>
status: rfc
toc: yes
confluence: https://confluence.example.com/spaces/ARCH/pages/12345/Language+Strategy
---

# Language Strategy
...
```

| Key | Meaning |
|-----|---------|
| `title` | Title in the tree and page header (defaults to the name) |
| `tags` | Comma-separated list (or YAML list); searchable with `Page: page/tags == "concept"` |
| `author`, `owner` | `Name <email@domain.com>`; shown as a `mailto:` link |
| `status` | Free text, e.g. `rfc`, `wip`, `approved` |
| `toc` | `yes` shows a table of contents |
| `confluence` | URL of the corresponding Confluence page, shown as a link |
| `name` | Optional unique name; defaults to the file name without `.md`. Files with the same name in different folders need an explicit `name` |

Markdown files without a frontmatter block are ignored.

## Page tree

A `PageMenu` lists its children. Pages come first, then sub-menus, each in the order written. A menu that
no other menu contains is a root.

```yaml
apiVersion: architecture/v1alpha1
kind: PageMenu
metadata:
  name: Handbook
  annotations:
    menu/title: Handbook
spec:
  contains:
    pages:
      - home
    menus:
      - Strategy
```

`archsight lint` reports pages that are in no menu or several menus, menu cycles and broken links.

## Home page

A page whose name or title is `Home` (any case) is shown at `/` instead of the generated architecture
overview. It stays a normal page: it is also listed in the tree and reachable at `/pages/home`.

## Content

- Tables, code blocks and other GitHub-flavoured markdown.
- Diagrams: fenced ```` ```asd ```` blocks (see [Diagrams](/doc/diagram)) replace draw.io drawings.
- Links: `[[Page title]]`, `[[page-name]]`, `[[Name|label]]` and `[[Kind/Name]]` link to pages and resources.

## Editing

With `archsight web --inline-edit`, a page can be edited in the UI (**Edit** on `/kinds/Page/instances/<name>`).
The form has the frontmatter keys as fields and the body as a markdown field (rich editor or plain text).
**Generate Markdown** shows the whole file, **Save to File** replaces it on disk. Saving fails with a
conflict if the file changed since the form was opened, and a file with broken frontmatter, without
frontmatter or with a changed name is rejected before it is written.

The saved frontmatter is rewritten in the order `title, tags, author, owner, status, toc, confluence`.
`name` and keys the form does not know are kept; YAML comments inside the frontmatter are not.

Inside the rich editor, an ` ```asd ` block shows a live [diagram preview](/doc/diagram#preview-in-the-editor).
