# Diagrams

Describe architecture diagrams in a small, nginx-like nested DSL with
graphviz-style connections, and render them to SVG with automatic
compound force-directed layout — no manual coordinates required.

Diagram sources use the `.asd` extension; generated SVG classes use the `asd-` prefix. The renderer is available as `Archsight::Diagram.render(source)` and through the `archsight diagram` command.

## Example

```
group "vpc" {
  label "Production VPC"

  group "public" {
    label "Public Subnet"
    component "lb" { label "Load Balancer" }
  }

  group "private" {
    label "Private Subnet"
    api "api_service" { label "API Service" }
    database "db" { label "Postgres" }
  }
}

actor "client" { label "Client" }

client -> lb
lb -> api_service
api_service -> db { style "orthogonal"; label "reads/writes" }
```


Ready-made sources live in `examples/diagrams/` (`archsight.asd` models archsight itself; `three_tier.asd`, `aws_vpc.asd` and `dag.asd` show containers, boundaries and ranks).

## Usage

```
archsight diagram examples/diagrams/aws_vpc.asd -o diagram.svg
archsight diagram aws_vpc.asd --watch              # re-renders on every save
archsight diagram three_tier.asd --relation=all    # also show control/data-flow edges
archsight diagram overview.asd --theme=compact     # denser spacing + smaller fonts (or cozy)
archsight diagram overview.asd --legend=bottom     # legend below (or right/left/top/none; default auto)
archsight diagram *.asd                            # render every file to its own .svg
```

`-o`/`--output` only makes sense with a single input file; with multiple
inputs (including a shell glob like `*.asd`) each one is rendered next to
itself with a `.svg` extension. `--watch` works with multiple inputs too,
re-rendering whichever file changed. If one input fails to parse, the rest
still render and the exit code reflects the failure.

## DSL reference

### Containers

- `group "id" { ... }` — a free-form nested container, laid out with a
  force-directed simulation.
- `layer "id" { ... }` — direct children are peers at the same rank,
  packed left-to-right on a shared centerline.
- `stack "id" { ... }` — direct children are packed top-to-bottom,
  first-declared on top, each stretched to the widest child ("runs on
  top of").
- `boundary "id" { ... }` — a trust/security zone; laid out like `group`
  but rendered with a distinct dashed warning-colored border.

Containers can nest freely — in particular, a `stack` of `layer`s (a
stack whose ranks are each internally peer-packed) is a natural way to
model a system with layered ranks where some ranks have several
alternatives at the same level, e.g. a kernel I/O stack: see
a `stack` of `layer`s.

### Ranks

A container can arrange its children in **ranks** by the edges between
them instead: every edge points from one rank to a later one, so a whole
dependency chain reads in one direction. Nodes in the same rank sit next
to each other, ordered to cross as few edges as possible. An edge points
from the dependent to its dependency (above it), except `implements`,
which puts the interface above its implementers. `ranks "<mode>"` inside
any container sets its mode; a top-level `ranks "<mode>"` statement sets
it for the diagram's own top level.

| mode | children are… |
|---|---|
| `auto` (default) | ranked top to bottom when the edges between them form a DAG at least 3 ranks deep; otherwise arranged as usual (opt in explicitly to rank a shallower one). Only for groups, boundaries and the top level: a `layer`/`stack` keeps its declared order |
| `on` | always ranked, in the container's natural direction: left to right in a `layer`, top to bottom everywhere else |
| `down` / `right` | always ranked, top to bottom / left to right |
| `off` | never ranked |

Nested containers each rank their own children, so a DAG of groups can
be ranked while a group inside it runs its own pipeline left to right.
Cycles are ranked too when asked
for explicitly (one edge of each cycle then points back up), but never
under `auto`.

```
group "pipeline" {
  ranks "right"
  component "ingest" { }
  component "clean" { }
  component "store" { }
}
ingest -> clean
clean -> store
```

### Leaves

- `component "id" { ... }` — a generic internal building block (rectangle).
- `application "id" { ... }` — a deployable system/app (rectangle, shaded
  distinctly from `component`).
- `api "id" { ... }` — an API/endpoint (circle).
- `database "id" { ... }` — a datastore (cylinder).
- `queue "id" { ... }` — a queue/topic (hexagon).
- `actor "id" { ... }` — an external user (stick figure, label below).

A leaf's shape can be overridden explicitly with `shape "rectangle" |
"circle" | "cylinder" | "hexagon" | "actor"`, though the keyword's default
covers the common case.

### Attributes

`key "value"` inside any block, e.g. `label "..."`. Every attribute and
value is checked when the diagram is built: an attribute that doesn't apply
to where it sits, a value outside its allowed set, or the same attribute
given twice in one block is an error naming the line (with a "did you mean"
hint for near misses), never silently ignored.

| attribute | on | values |
|---|---|---|
| `label` | everything | any text (see *Label text*) |
| `tint` | nodes, containers, edges | `gray`, `blue`, `indigo`, `purple`, `pink`, `red`, `orange`, `yellow`, `green`, `teal`, `cyan`, `brown` |
| `link` | nodes, containers | `http(s)://…`, `mailto:…` or a relative URL |
| `resource` | nodes, containers | a resource name (`Archsight:Web`) or `Kind/Name` (`ApplicationService/Archsight:Web`); see *Linking to resources* |
| `extend` | nodes, containers | `true`, `false`; containers also `height` |
| `shape` | leaves | `rectangle`, `circle`, `cylinder`, `pipe`, `actor`, `file`, `module` |
| `gap` | containers | pixels (`40`), a percentage (`150%`) or a signed one (`+20%`, `-50%`) |
| `ranks` | containers | `auto`, `on`, `down`, `right`, `off` |
| `columns` | containers | a positive integer |
| `style` | edges | `straight`, `orthogonal` |
| `relation` | edges | `dependency`, `implements`, `control`, `data` |
| `color` | dataflows | a hex color such as `#1a56db` |

`no-gap` and `no-extend` are shorthand for `gap "0"` and `extend "false"`.
A dataflow with a repeated hop, a duplicate dataflow id, a node with an
empty id, and an edge from a node to itself are errors too.

- `link "https://..."` — on any node (leaf or container), turns its
  shape and its whole label into a clickable link (an SVG `<a>`, with a
  pointer cursor and hover affordance) — effectively a "button" in the
  diagram.

#### Label text

Any label anywhere (node, container, edge, dataflow) supports:

- A small inline markdown-lite: `**bold**`, `*italic*`, `__underline__`,
  and `[text](url)` for a link on just that run of text (independent of
  a node-level `link` — a label can have both, or just one).
- Multi-line text, written either with an explicit `\n` escape
  (`label "Line one\nLine two"`) or by literally spanning multiple lines
  in the source; in the latter case each line's leading/trailing
  whitespace is trimmed automatically, so the `.asd` file's own
  indentation doesn't leak into the rendered label:
  ```
  label "First line
         Second line"
  ```

### Edges

`from OP to` / `from OP to { attrs }`, declared anywhere at any nesting
level, where `OP` is:
- `->` — directed (default).
- `<->` — bidirectional (arrowheads on both ends).
- `--` — undirected (no arrowheads).

Edges between boxes that sit one above the other (or side by side) and overlap on the other axis are drawn as a single straight axis-aligned line when nothing is in the way, e.g. many components dropping straight down onto one wide database. An explicit `style "orthogonal"` keeps its right-angle turns.

Edge attributes:
- `label "..."` — text drawn along the edge.
- `style "straight" | "orthogonal"` — routing style (default: `straight`).
- `relation "dependency" | "implements" | "control" | "data"` — the kind
  of relationship (default: `dependency`). `implements` renders as a
  dashed line with a hollow UML-style arrowhead. Rendering is
  dependency-first: only `dependency`/`implements` edges are drawn unless
  you pass `--relation=`, though layout always accounts for every edge
  regardless of what's shown.

### Dataflows

`dataflow "id" { hop "..."; hop "..."; ...; color "#hex"; label "..." }`
— an ordered, multi-hop path (2+ `hop`s, each a node id), declared
anywhere at the top level. Unlike an edge, a dataflow always renders
(unaffected by `--relation=`) as one uninterrupted line running through
every hop in order, with a single arrowhead at the final hop rather than
one per hop. Useful for showing a real end-to-end path (e.g. a request
crossing several intermediate systems) as a single visual/routing unit
instead of `hops.length - 1` independent edges.

- `hop "id"` — one path segment's next node, in order.
- `color "#hex"` — the line's stroke color (default: the same green used
  for a `data`-relation edge).
- `label "..."` — text drawn once, near the path's middle hop.

```
dataflow "checkout_request" {
  hop "client"
  hop "gateway"
  hop "checkout_service"
  hop "db"
  color "#1a56db"
  label "checkout request"
}
```

### Theme

A top-level `theme` statement picks the diagram's spacing and font sizes:

```
theme "compact"
```

From roomiest to densest:

| theme | for | node label font |
|---|---|---|
| `default` | small diagrams; used when there's no `theme` statement | 13px |
| `cozy` | mid-sized diagrams: roughly halfway between the two | 12px |
| `compact` | large diagrams that would otherwise sprawl | 11px |

`cozy` and `compact` shrink container padding, sibling gaps and node
sizes along with the fonts, and size each node from its label's real
Helvetica glyph widths so boxes hug their text. `--theme=NAME` on the CLI (or `theme:` in
`Archsight::Diagram.render`) overrides the file's own choice. The legend
isn't affected.

### Legend

A legend is added automatically, listing only the shapes, relations,
boundary styles and dataflows actually used. It's left out entirely for a
plain diagram of components and dependency edges.

It's laid out like the rest of the drawing: a `layer` of `stack`s (its
columns), each only as wide as its own entries. It then goes beside the
diagram, which it never moves:

- **wide diagram** → below it, in as many columns as fit its width;
- **tall diagram** → to its right, in as few columns as fit its height.

A top-level `legend "..."` statement overrides this: `bottom`, `right`,
`left`, `top`, `none` (no legend), or `auto` (the default).
`--legend=MODE` (or `legend:` in `Archsight::Diagram.render`) overrides the
file's own statement. Lines are routed around the legend, never through
it.

```
legend "right"
```

## Linking to resources

`resource` links a node to an archsight resource, so a diagram is a map of
the model you can click through:

```
component "web" { label "Web server"; resource "Archsight:Web" }
layer "cli" { label "CLI subsystem"; resource "ApplicationService/Archsight:CLI" }
```

Inside the web UI the reference is looked up in the resource database and
the node becomes a link to `/kinds/<Kind>/instances/<Name>` (clicking it
navigates in-app). A bare name is searched in every kind; when the same
name exists in several, write `Kind/Name`. `link` and `resource` can't share
a node -- use `link` for external URLs.

A reference that doesn't resolve never breaks the diagram: the node is drawn
dashed and dimmed with a "Resource … not found" tooltip, and `archsight lint`
reports it with the node and line (a rename or typo is caught the same way
a broken `[[Name]]` link would be). Standalone `archsight diagram` has no
resource database, so there `resource` is accepted but inert -- no link and
no broken styling. Library users pass a `resolver:` to `Diagram.render`
(any `call(reference)` returning a URL, `:missing` or `:ambiguous`, see
`Archsight::Helpers::ResourceResolver`) and, to collect failures, `unresolved: []`.

## Diagrams in markdown

A fenced code block tagged `asd` in any markdown the web UI renders (docs,
the `architecture/description` annotation, analysis text) is drawn as an
inline SVG instead of shown as source:

````
```asd
component "web" { label "Web" }
component "db" { label "DB" }
web -> db { relation "data" }
```
````

Each diagram's element ids are prefixed with a hash of its source
(`Archsight::Diagram.render(src, id_prefix: "...")`), so any number of
diagrams can share a page without colliding. A block that fails to parse
shows the error above its source rather than breaking the page, and
`archsight lint` reports it as an error. Other renderers (GitHub, the
terminal) still show the block as plain code.

### The `architecture/diagram` annotation

For a diagram that belongs to a resource as a whole, put the `.asd` source in
the `architecture/diagram` annotation (no fence needed):

```yaml
metadata:
  name: Archsight
  annotations:
    architecture/diagram: |
      component "web" { label "Web" }
      component "db" { label "DB" }
      web -> db { relation "data" }
```

The instance page shows it first, with a **Diagram / Dependencies** toggle to
swap to the auto-generated dependency graph (resources without the annotation
show the graph as before). `archsight lint` reports a definition that doesn't
render, and the editor offers it as a multi-line field.

## SVG element ids

Every drawn element carries an `id` tying it back to the source object it
was drawn for, so a script or stylesheet can target it and two renders can
be compared object by object. Ids are computed in declaration order, so an
object keeps its id as long as its own source doesn't change.

| Source | Wrapping `<g>` | Parts (`<g>` id + `__part`) |
|---|---|---|
| node / container `"db/main"` | `asd-node-db_main` (a container's `<g>` also holds its children's) | `__body`, `__cap`, `__fold`, `__head`, … / `__frame`; `__label` |
| edge `api -> db/main` | `asd-edge-api__db_main` (`__2`, `__3`, … for repeats of the same pair) | `__line`, `__hit`, `__label` |
| implements tree onto `iface` | `asd-tree-iface` (each stub keeps its own edge `<g>`) | `__spine`, `__trunk` |
| dataflow `"provision"` | `asd-dataflow-provision` (a `hop group`'s pieces: `…__prefix`, `__suffix`, `__branch0`, …) | `__halo`, `__line`, `__label` |
| legend | `asd-legend`, rows `asd-legend-shape-Datastore`, `asd-legend-relation-data`, … | `__bg`, `__title`; rows' `__icon`, `__label` |

A source id is slugged down to `[A-Za-z0-9_-]` (anything else becomes
`_`, runs of `_` collapse), so ids work as CSS selectors unescaped, and
`__` only ever separates parts. When two ids slug to the same token, the
later one gets `-2`, `-3`, …; an id that's already clean always keeps its
own. Each object's `<g>` also carries `data-asd-kind` (the DSL keyword:
`component`, `group`, …, `edge`, `dataflow`), `data-asd-src` (the exact
source id, or `data-asd-from`/`data-asd-to` for an edge), and
`data-asd-line` (its source line). Labels are painted in a separate text
layer on top of everything else, outside that `<g>`, so they carry
`data-asd-owner` (the `<g>`'s id) and `data-asd-line` themselves. To
find an element's source line, use `el.closest('[data-asd-line]')`.

## Hover highlighting

In a browser, hovering an edge highlights it and its label: its line gets
thicker, its label goes bold, and every other edge fades. Hovering a node
does the same for its outgoing edges. For a group, layer, stack or
boundary, that means hovering its frame or title, not a node inside it,
and only edges declared on the container itself count. Each edge carries
an invisible, wider `__hit` path over its line so thin lines are easy to
hover.

It's pure CSS (`:has()` rules generated per edge and node), embedded
even with `--style=none`. That means it works wherever the SVG's
`<style>` survives: opened directly, inlined into HTML, or via
`<object>`. It doesn't work in an `<img>`.

## Development

```
bundle exec rake compile      # (re)build the optional native extension
bundle exec rake test         # Minitest suite (test/diagram is part of it)
ruby bench/run.rb 10x10 20x10 # render synthetic diagrams, print stage timings
```

The routing and label-placement hot loops have an optional C implementation
(`ext/archsight_diagram_native`). On a 400-node synthetic diagram it takes the render
from about 25 s to about 0.3 s. It produces byte-identical output to the
pure-Ruby code, which is still used whenever the extension isn't built. Set
`ARCHSIGHT_DIAGRAM_NATIVE=0` to force pure Ruby.
