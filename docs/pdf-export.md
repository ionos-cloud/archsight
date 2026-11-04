# PDF Export

Every [page](/doc/pages) and every resource can be downloaded as a PDF. The document is typeset by [Typst](https://typst.app),
so the server (or the machine running the CLI) needs the `typst` command; the container image has it, together with
`rsvg-convert` (turns diagrams into vector graphics), `dot` of Graphviz (draws the dependency graph) and a few fonts.

## Getting a PDF

- **Web UI:** the **PDF** button next to **Edit** on a page or resource.
- **API:** `GET /api/v1/pages/{name}/pdf` and `GET /api/v1/kinds/{kind}/instances/{name}/pdf`, see the [REST API documentation](/docs/api).
  The response has an `ETag` that changes whenever the page, an image, a diagram or the template changes.
  Query parameters: `template` (name of a pdf Config) and `draft=1` (watermark).
- **CLI:** `archsight pdf <page>` or `archsight pdf Kind/Name`, with `-o file.pdf`, `--template` and `--draft`.

Without `typst` the API answers `503` and the button shows the reason.

## What is in the document

- A **page** is typeset as written: headings, text, tables (with their alignment), task lists, code, images next to the page,
  `asd` diagrams (as vector graphics), `[[links]]` (as their label), `{status:...}` (a coloured box), `{jira:KEY}` (a link
  when `jira.issue_url` is set) and `{emoticon:...}`. Macros that need the running application (`{children}`) are left out.
  Mermaid blocks and draw.io images cannot be drawn on the server: a note stands there (and the Mermaid source).
- **Tables** have horizontal rules only: a stronger one under the header row and a light one under every other row, no frame
  and no vertical lines, in the muted colour of the Config; the first column is flush with the text.
- **Live content is the data of the moment of the export**, as in the Confluence export:
  - `![[View/Name]]` and ```` ```view ```` blocks are tables (title, number of items, repeated header row; long columns
    share the width), `` ```requirements `` blocks are the requirements table.
  - `![[Analysis/Name]]` runs the analysis and puts its sections (headings, text, tables, lists, messages) into the document.
    An analysis runs for as long as its own `analysis/timeout` allows, so at most 5 run per document (`pdf.max_analyses`),
    and a result is reused for a minute. A failed analysis shows its error.
  - `![[Kind/Name]]` of another kind is the resource's description.
  - Only an embed on a line of its own (or several, one per line) is content; inside a sentence it stays its name.
  - What cannot be shown (unknown or ambiguous reference, an invalid view or requirements block) is a visible note in the
    document, never blank space. Embeds inside an embedded description are not expanded again.
- **Images by URL** (`![](https://...)`) are fetched by the server so they can go into the PDF. Only public hosts on https/http
  are contacted (never loopback, private or link-local addresses, so the server cannot be used to reach the network
  behind it), at most 10 MB and 10 seconds each, and only real png, jpeg, gif or webp files are used; otherwise the alt text
  is shown. `pdf.remote_images: false` turns this off.
- Any other **resource** becomes a generated document: its description, its properties, its relations and its
  `architecture/diagram`, and its **dependency graph**, shown first, as on its page (the resources its relations lead to, two steps
  deep, following its own layer and the one below it, nodes coloured by layer), drawn by `dot` in the direction, left to
  right or top to bottom, in which it is larger on the page. A resource without
  relations has no graph, and without `dot` the document is made without it. Properties are a label and value list (related annotations kept together; lists as "a, b";
  multi-line and markdown values as sections of their own). Relations are shown in both directions, **Outgoing** (what this
  resource points to) and **Incoming** (what points to it, read from the other side): the relation is named once, with the
  kind next to it and the resources flowing in two columns, so a resource with many relations stays readable.

## Steering the layout with tags

Tags of the page (`tags:` in the frontmatter) or of a resource (`architecture/tags`):

| Tag | Effect |
|-----|--------|
| `pdf:cover` | A cover page (logo band, title, id, version, date, owner) instead of the title block |
| `pdf:toc` | A table of contents |
| `pdf:landscape` | Landscape pages |
| `pdf:draft` | A "draft" watermark on every page |
| `pdf:no-graph` | Leave the dependency graph out of a resource's document |
| `pdf:no-breaks` | Ignore the page breaks before headings that the Config asks for (`pdf/break-before`, `pdf/keep-space`) |
| `pdf:template:<name>` | Use the pdf Config `<name>` instead of `default` |
| `version:<x>` | The document version in the header (else the page property `Version`, else `1`) |

Further page data used by the layout: `title`, `owner` (else `author`), `updated` (else today), and the page properties
`Document ID` (default `Kind/name`) and `Classification` (red marking in the footer, default from the template).

## The look: Config

A `Config` resource (layer *Other*) holds settings of a feature of the tool, kept with the model; `config/type` says
which feature. The PDF export reads the Configs of type `pdf`: colours, fonts, logo and the text around the pages. The one
named `default` is used for every document that does not name another (`pdf:template:<name>`); `brand`, `PDF:brand` and
`Config:PDF:brand` all name the same Config. Without any a neutral look is used. A Config of another type is never used
for the PDF, so every feature can have its own `default`. (The per-user file with tokens and URLs stays
[`~/.config/archsight/archsight.yaml`](/doc/configuration).)

```yaml
apiVersion: architecture/v1alpha1
kind: Config
metadata:
  name: Config:PDF:default
  annotations:
    config/type: pdf
    pdf/color-primary: "#1f3a5f"
    pdf/color-accent: "#2f7fd1"
    pdf/logo: assets/logo.svg
    pdf/logo-light: assets/logo-white.svg
    pdf/footer-text: Generated with Archsight
    pdf/classification: Internal
    pdf/font-body: Open Sans
    pdf/font-dir: assets/fonts
spec: {}
```

| Annotation | Meaning |
|------------|---------|
| `config/type` | `pdf` for these settings |
| `pdf/color-primary`, `-accent`, `-text`, `-muted`, `-ok`, `-warn`, `-danger` | Hex colours (`#rrggbb`) |
| `pdf/font-body`, `-heading`, `-mono` | Font families, tried before the built-in fallbacks |
| `pdf/font-dir` | Directory (relative to the resources directory) with font files (ttf, otf) that ship with the model |
| `pdf/logo`, `pdf/logo-light` | svg or png, relative to the resources directory. `logo` is shown on white (page header), `logo-light` on the cover band |
| `pdf/footer-text`, `pdf/classification` | Texts in the footer of every page |
| `pdf/header-meta` | Parts of the header line: `id, version, date, owner` |
| `pdf/lang` | Language of the fixed texts: `en` or `de` |
| `pdf/paper`, `pdf/margin` | `a4`, `a5` or `us-letter`; horizontal margin such as `16mm` |
| `pdf/break-before` | Heading levels that always start a new page, e.g. `1` or `1,2` |
| `pdf/keep-space` | `level:share` pairs: a heading of that level starts a new page when less than the share of the page is left, e.g. `2:30%` or `2:30%,3:20%` |

The first heading of a document never breaks (it follows the title block or the contents). A level in `pdf/break-before` needs no
share in `pdf/keep-space`. Without these settings headings flow as before (Typst keeps a heading with the text after it).

Values are checked when they are loaded (and by `archsight lint`): something that is not a colour, a font name or a length is
ignored and the default is used.

## Seeing the look

The page of a Config of type `pdf` shows its settings as they look (the colours, the fonts, the logo on white and on
the cover band, the page settings) and, beside them, a **preview**: a fixed sample document (a cover page and a page with
headings, a list, a quote, a table with status badges and code) typeset by the server with exactly these settings, one
tab for the cover and one for the page. It shows the saved Config; after an edit the page typesets it again.
The same sample is `GET /api/v1/kinds/Config/instances/{name}/preview` (`?part=cover` or `?part=page` for one page).

## Settings

`pdf.typst` (`ARCHSIGHT_PDF_TYPST`) is the path of the `typst` command if it is not on the `PATH`, `pdf.dot` (`ARCHSIGHT_PDF_DOT`) the same for `dot`, `pdf.timeout`
(`ARCHSIGHT_PDF_TIMEOUT`) the seconds a document may take (default 60), `pdf.remote_images` (`ARCHSIGHT_PDF_REMOTE_IMAGES`) `false` to never fetch images by URL, `pdf.max_analyses` (`ARCHSIGHT_PDF_MAX_ANALYSES`) the number of analyses one document may run (default 5). See [Configuration](/doc/configuration).
