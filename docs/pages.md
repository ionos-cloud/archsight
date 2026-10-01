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

## Images and draw.io diagrams

Images and [draw.io](https://www.drawio.com) diagrams are plain files in the resources directory, usually right next
to the page that shows them (add them to the repository like pages). Markdown embeds them with the usual image syntax
and a relative path:

```markdown
![Overview](overview.png)
![Deployment](../fop/deployment.drawio)
![Flow](flow.asd)
```

A reference is resolved against the folder of the file that contains it, and the result is a path relative to the
resources directory:

| Markdown file | Reference | File |
|---------------|-----------|------|
| `pages/handbook/home.md` | `../img/a.png` | `pages/img/a.png` |
| `pages/handbook/home.md` | `../../fop/bar.drawio` | `fop/bar.drawio` |
| `pages/handbook/home.md` | `../../../x.png` | not allowed, it would leave the resources directory |

This works in pages and in the `architecture/description` of any resource (relative to the YAML file that defines
it). Images are shown inline; a `.drawio` file is shown by the draw.io viewer, read-only, with its page selector,
zoom and layer controls and a link to the file. An `.asd` file ([Archsight diagram](/doc/diagram)) is rendered like an
```` ```asd ```` block, with links to your resources, and the lint reports it if it does not render. The API serves the rendered SVG
for it, not the source.

"Assets" is the name of the only way to them: the browser never reads these files directly, it asks
`/api/v1/assets/<path>` (the path of the file relative to the resources directory), and that endpoint decides what
is served:

- **Types**: png, jpg, gif, webp, avif, svg, drawio and asd, up to 25 MB. Everything else is not served, in particular
  the resource definitions themselves (`.yaml`, `.md`), sources and anything with an unknown type.
- **Nothing outside the resources directory.** `..` is resolved first and a path that would leave the directory is
  rejected, as are absolute paths, backslashes, hidden files and folders (`.git`, `.env`) and symlinks that point
  out. A file that is outside, missing or of another type gets the same 404.
- **Keep the resources directory dedicated.** Every file of an allowed type below it can be fetched, and the default
  resources directory is the working directory (`ARCHSIGHT_RESOURCES_DIR`). Do not point Archsight at a directory
  that also holds images you do not want to publish.
- **Broken references** are shown as a red, wavy marker (with the reason as tooltip) and reported by
  `archsight lint`: outside the resources directory, no such file, type not served.
- **Self-hosted viewer**: the official draw.io viewer ships with Archsight (`lib/archsight/web/public/vendor/drawio`,
  Apache-2.0, upgrade with `script/vendor_drawio`). It loads nothing from other hosts, a policy on its page blocks
  such requests, so an image embedded in a diagram from an `https://` URL is not shown. Formulas are not typeset.
- **Kubernetes**: binary files do not fit a ConfigMap (1 MB limit), provide the resources with git-sync or a volume.

## Home page

A page whose name or title is `Home` (any case) is shown at `/` instead of the generated architecture
overview. It stays a normal page, reachable at `/pages/home`, and needs no menu: it is not listed under
"Unsorted" and `archsight lint` does not ask for one. Put it in a menu if you also want it in the sidebar tree.
If several pages qualify, a page named `home` wins over one that is only titled Home.

## Content

- Tables, code blocks and other GitHub-flavoured markdown.
- Diagrams: fenced ```` ```asd ```` blocks (see [Diagrams](/doc/diagram)) replace draw.io drawings.
- Links: `[[Page title]]`, `[[page-name]]`, `[[Name|label]]` and `[[Kind/Name]]` link to pages and resources.

## Editing

With `archsight web --inline-edit`, a page can be edited in the UI (**Edit** on `/kinds/Page/instances/<name>`).
The form has the frontmatter keys as fields and the body as a markdown field (rich editor or plain text).
**Generate MD** shows the whole file, **Save to File** replaces it on disk. Saving fails with a
conflict if the file changed since the form was opened, and a file with broken frontmatter, without
frontmatter or with a changed name is rejected before it is written.

The saved frontmatter is rewritten in the order `title, tags, author, owner, status, toc, confluence`.
`name` and keys the form does not know are kept; YAML comments inside the frontmatter are not.

Inside the rich editor, an ` ```asd ` block shows a live [diagram preview](/doc/diagram#preview-in-the-editor).

## Pages and AI assistants (MCP)

`archsight web` serves an MCP server (see the [README](https://github.com/ionos-cloud/archsight#mcp-server)).
It has no page-specific tools: pages are ordinary resources of the kinds `Page` and `PageMenu`, so the generic
tools reach them. It is read-only, pages cannot be created or edited through MCP.

**Finding pages**

1. Ask for totals or names first, this is cheap: `query` with `Page:` and `output: "count"` or `"brief"`.
   `brief` returns the page names (file names) only, not titles, tags or status.
2. Narrow down with the [query language](/doc/search#searching-wiki-pages), for example
   `Page: page/tags == "howto"`, or search the text with `Page: page/content =~ "asd"`. A bare word matches the
   name only, so full-text search always goes through `page/content`.
3. Read one page with `analyze_resource` (`kind: "Page"`, `name: "<page name>"`): the result has the
   metadata (`page/title`, `page/tags`, `page/status`, ...) and the raw markdown in `page/content`.

**Reading the tree**: `PageMenu: <- none` returns the root menus. `analyze_resource` with `kind: "PageMenu"`
returns `relations.contains` with the names of its pages and sub-menus. The `spec` field of that response lists
the same targets as `#<Archsight::Resources::...>` strings, use `relations`. The home page is
`Page: name == "home"`. The [REST API](/docs/api) returns the whole tree in one call (`GET /api/v1/pages`).

**Keep responses small.** `output: "complete"` and `"annotations"` include the whole markdown of every match,
and the default limit is 50: for the 11 pages of the example handbook that is more than 25 KB, against well under 1 KB with `brief`. Use `limit`, or find the page
names with `brief` and read pages one at a time.

**Escaping.** Tool arguments are JSON, so the doubled backslash of a regex (`\\[`, see
[search](/doc/search#searching-wiki-pages)) is written `\\\\[` inside the JSON string.

