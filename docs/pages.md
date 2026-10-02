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
created: 2026-01-12T09:30:00Z
updated: 2026-03-02
properties:
  Git Repository: https://git.example.com/org/language-strategy
  Ticket: "{jira:ARCH-42}"
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
| `author`, `owner` | `Name <email@domain.com>` or just a name; with an email shown as a `mailto:` link |
| `created`, `updated` | ISO 8601 date or time (`2026-01-12`, `2026-01-12T09:30:00Z`). The inline editor sets `updated` when it saves a changed page; the Confluence import fills both from the page history |
| `properties` | Everything else you want to record, as a mapping of `key: value` pairs (kept in order, shown in the page header, URLs as links, `{jira:KEY}` works). In the API and in queries it is `page/properties`, one `Key: value` per line |
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

A menu can have a page of its own, like a Confluence page that has child pages. `opens` names it:

```yaml
kind: PageMenu
metadata:
  name: Strategy
  annotations:
    menu/title: Strategy
spec:
  opens:
    pages: [strategy-overview]   # the title of the menu links to this page
  contains:
    pages: [language-strategy]
```

In the sidebar the arrow of such a menu only unfolds it and the title opens the page, so you can browse the tree without
changing the page; the menu opens by default while you read its page or one below it. The page is not listed a second time
inside the menu, its breadcrumb starts above the menu, and the breadcrumb entries of menus that open a page are links. A menu
opens at most one page, and that page must not be in another menu.

`archsight lint` reports pages that are in no menu or several menus, menus that open several pages or also contain the page
they open, menu cycles and broken links.

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

## Embedding views and analyses

`![[View/Name]]` and `![[Analysis/Name]]` show the live content of a view (its result list) or an analysis (its
result) inside a page, or in the description of any resource:

```markdown
![[View/View:ServiceDependencies]]
![[Analysis/Analysis:Service:Count]]
```

The page is shown immediately. Each embed loads on its own, with a spinner, and an analysis runs when the page opens
(it can be run again from the embed), so a slow query or script never delays the text around it. The embed
links to the view or analysis page. The server only writes a placeholder: rendering a page (`GET /api/v1/pages/{name}`)
never runs a query or a script, and API or MCP consumers get `<div class="kind-embed" data-kind data-name>` with a plain
link to the resource. Other kinds are not embeddable; an unknown name, another kind or an embed written inline in
a sentence (instead of on its own line) is shown as a marker or a link, and `archsight lint` reports embeds that do not
resolve. Code blocks and inline code are left alone.

## Macros

Inline macros are written `{name:arguments}` and named like the macros of Confluence. They work inside a sentence, a
heading, a list or a table cell, and are left alone in code. The arguments cannot contain `{`, `}`, `|` or a line break
(a `|` would make the line a table row). Anything that is not a macro, or a macro with arguments it does not accept, stays
as written, so braces in prose are safe; `archsight lint` reports a known macro with bad arguments.

| Macro | Example | Shows |
|---|---|---|
| `status` | `{status:yellow WIP}` | a coloured lozenge; colours `grey`, `red`, `yellow`, `green`, `blue`, `purple`, text of 1 to 40 characters |
| `emoticon` | `{emoticon:2705}`, `{emoticon:2705 check mark button}`, `{emoticon:minus}` | an emoji by its hex code point(s) (`1f468-200d-1f4bb` for a sequence) and an optional name, or one of the classic Confluence emoticons by name: `smile`, `sad`, `cheeky`, `laugh`, `wink`, `thumbs-up`, `thumbs-down`, `information`, `tick`, `cross`, `warning`, `plus`, `minus`, `question`, `light-bulb-on`, `light-bulb-off` and the `yellow-star`, `red-star`, `green-star`, `blue-star` |

The lozenge is an image generated by `GET /api/v1/status/{colour}/{text}.svg` (the `.svg` is optional), cached for good as
the URL fully determines it. The Confluence export writes them as the native Confluence macros (`status`, `emoticon`, `jira`), and
the import of a Confluence page does the same the other way round.

| `jira` | `{jira:PROJ-123}` | a link to the Jira issue |
| `children` | `{children}`, `{children:all sort=title}` | the child pages of the page it is on: the contents of the menu that opens the page |
| `pagetree` | `{pagetree}`, `{pagetree:root=handbook sort=title}` | the page tree below a page, all levels, the page itself on top |

The Jira link is built from the `issue_url` setting, a URL with `{issue}` in it, in `~/.config/architecture/jira.yaml`
(`ARCHSIGHT_JIRA_CONFIG` names another file, `ARCHSIGHT_JIRA_ISSUE_URL` overrides the file):

```yaml
issue_url: https://jira.example.com/browse/{issue}
```

Only that field is read. Without it the key is shown as code, without a link.

`children` takes options separated by spaces: `depth=N` (levels, default 1), `all` (every level), `sort=title` (default: the
order of the menu) and `reverse`. A sub-menu is one entry, linked to the page it opens; a page that no menu opens has no
children. In Confluence it becomes the native children macro.

`pagetree` is the same data with every level and the root page as the first entry. Its options are `root=PAGE` (the name of a page, default: the page the macro is on), `sort=title` and `reverse`; Confluence's `startDepth`, `searchBox` and the like are not supported. It becomes the native page tree macro.

A new macro is a module with `parse(arguments)`, `html(value)`, `confluence(value)` and `problem(arguments)` registered with
`Archsight::Helpers::Macros.register("name", handler)` (see `lib/archsight/helpers/macros/`).

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

## Exporting to Confluence

`archsight export --to confluence [PAGE...]` publishes pages to the Confluence page named in their `confluence:` frontmatter
(Confluence Data Center; a page URL such as `https://host/spaces/KEY/pages/12345/Title`, `.../pages/viewpage.action?pageId=12345`
or `.../display/KEY/Title`). Without `PAGE` every page that has a `confluence:` link is exported.

```bash
archsight export --to confluence -r resources                 # all linked pages
archsight export --to confluence handbook-home --dry-run      # show what would happen
archsight export --to confluence handbook-home --force        # overwrite changes made in Confluence
```

**Page properties**: the frontmatter is exported as a Page Properties table (the `details` macro) above the body, so Confluence
keeps its property reports working: Document status (a status lozenge; `wip`/`draft` yellow, `rfc`/`review` blue,
`approved`/`done`/`ga` green, `deprecated`/`rejected` red, anything else grey), Document owner, Document author, Teams (the
`Team:<name>` tags), Tags and every entry of `properties`. People are written as their name. `created` and `updated` are not
exported. The Confluence import (not part of Archsight) does the reverse, which is why `Team:` tags and `properties` exist.

**Credentials** work like the Jira token, with a personal access token: `CONFLUENCE_TOKEN`, or the `token:` field of
`~/.config/architecture/confluence.yaml` (`--credentials PATH` for another file). The host comes from the page URL. The token
is never printed. If the Confluence has the draw.io app, add `drawio: true` to the same file (or `CONFLUENCE_DRAWIO=true`,
`--drawio` / `--no-drawio` per run):

```yaml
token: <personal access token>
drawio: true
```

**What is exported**: headings, text, tables, lists, links, code (code macro), a table of contents when `toc: yes`, images
(attachments) and diagrams, which depend on `drawio`:

| In the page | `drawio: true` | `drawio` off (default) |
|-------------|----------------|------------------------|
| `![](x.drawio)` | draw.io macro (diagram + PNG preview attached) | image (PNG of the diagram), the `.drawio` attached |
| `![](x.asd)`, ```` ```asd ```` | draw.io macro holding the diagram's SVG | image (PNG when `rsvg-convert` is installed, else SVG), SVG attached |
| `![](x.svg)` | draw.io macro holding the SVG | SVG attachment |

With `drawio` off nothing draw.io-specific is written, so any Confluence shows the diagrams. Rendering a `.drawio` needs the
draw.io desktop CLI (`drawio`, or `ARCHSIGHT_DRAWIO_CLI`) on the machine that exports; the preview of an SVG needs
`rsvg-convert` or that CLI. A diagram that cannot be rendered fails the page instead of leaving a blank diagram. Attachments an
earlier export added and the page no longer uses are removed; attachments added by others are left alone. `[[links]]` to pages that have a Confluence link
become links to them, other links are plain text; embedded views and analyses (`![[View/..]]`) become a note, their content
is live and exists in Archsight only. A page with a broken image or a diagram that does not render is not exported and
reported as failed. The Confluence title is kept.

**Links in diagrams**: a node with `resource "Some Page"` links to the Confluence page of that wiki page (the page's own
`confluence:` link) instead of its Archsight address, which means nothing in Confluence. A reference to a page without a
Confluence link, or to any other resource, is drawn as a plain node. Unknown or ambiguous references stay dashed, as in the web
UI. The web UI itself is not affected. A picture cannot be clicked, so with `drawio` on the export lays an invisible clickable
area with the link over every linked node of the draw.io diagram (the link opens the Confluence page); with `drawio` off the
links exist in the attached SVG only.

**Protection against lost edits**: after each export a marker (a content property `archsight` with the version that was
written) stays on the page. A page is only overwritten while Confluence still has that version. A page that Archsight did not
export before, or that was edited in Confluence since, is **not exported**: it is reported as `NOT EXPORTED (blocked)` with who
changed it and when, and the command exits with 1. `--force` overwrites it anyway; the new version's message says which edits
were replaced. A page whose generated content is unchanged is left alone (no new version).

**Locking and revisions**: unless `--no-lock`, editing is restricted to the exporting user (if the server does not allow it,
the export still succeeds and says "NOT locked"). Every exported version has the message "Generated by Archsight <version> from
<file>, do not edit in Confluence", and the page starts with a note that it is generated and that the source file is the place
to edit.

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
returns `relations.contains` with the names of its pages and sub-menus and `relations.opens` with the page its title links to. The `spec` field of that response lists
the same targets as `#<Archsight::Resources::...>` strings, use `relations`. The home page is
`Page: name == "home"`. The [REST API](/docs/api) returns the whole tree in one call (`GET /api/v1/pages`).

**Keep responses small.** `output: "complete"` and `"annotations"` include the whole markdown of every match,
and the default limit is 50: for the 11 pages of the example handbook that is more than 25 KB, against well under 1 KB with `brief`. Use `limit`, or find the page
names with `brief` and read pages one at a time.

**Escaping.** Tool arguments are JSON, so the doubled backslash of a regex (`\\[`, see
[search](/doc/search#searching-wiki-pages)) is written `\\\\[` inside the JSON string.

