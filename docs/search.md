# Query Syntax

The search box supports a powerful query language for filtering architecture resources.

## Quick Start

| Query | Description |
|-------|-------------|
| `kubernetes` | Name contains "kubernetes" (in the search box: also the text, ranked) |
| `TechnologyArtifact:` | All resources of a specific kind |
| `activity/status == "active"` | Annotation equals value |
| `scc/loc == 15000` | Numeric equality |
| `activity/status?` | Annotation exists (is set) |
| `! activity/status?` | Annotation doesn't exist |
| `-> ApplicationInterface` | Has relation to a kind |
| `text: "failover standby"` | Full-text search: the text contains both words, best matches first |

## Name Search

In the **search box**, words find resources by name and by text: `kubernetes failover` lists everything whose name
contains both words or whose text (descriptions, titles, page content, ...) contains both, also as the beginning of
a longer word (`kube` finds kubernetes). The best matches come first, see [Ranking](#ranking). Mixed with a
condition the words are one part of the query: `kubernetes failover & activity/status == "active"`.

In saved views, embedded `view` blocks, sub-queries and the MCP `query` tool a bare word is a name search only
(case-insensitive regex match), so their results do not change:

    kubernetes              # name =~ "kubernetes"
    name == "MyService"     # exact match
    name =~ "repo-.*"       # regex pattern
    name != "OldService"    # not equal
    name in ("a", "b")      # name is one of several options

Names often contain colons (`Archsight:CLI`) and so do [aliases](/doc/modeling#identity-and-links) (`ITGS:A001`). Typed
without spaces they are one word, found by name or alias like any other bare word:

    Archsight:CLI           # the resources named Archsight:CLI
    ITGS:A001               # the resource with the alias ITGS:A001
    ApplicationService:ITGS:A001   # the same, in one kind

## Text Search

`text` searches the content of resources: every string annotation (descriptions, titles, `link/*`, page content, ...).
A quoted string is a **full-text search** in an index of all texts:

    text: "failover"                    # the word failover (also failovers: word forms are found)
    text =~ "failover"                  # the same
    text: "failover standby"            # both words, anywhere in the resource
    text: "failover OR standby"         # one of them
    text: "failover NOT region"         # failover, but not region
    text: "\"active standby\""          # the exact phrase (quotes inside the string)
    text: "kube*"                       # words that start with kube
    text: "PROJ-1234"                   # words with - : / . are searched as written, next to each other
    ApplicationService: text: "failover" & -> ApplicationComponent   # combined with anything else

Words are case-insensitive and accents are ignored. `AND`, `OR` and `NOT` are operators only in capitals; parentheses
group. The hits of a full-text search come ranked by relevance, see [Ranking](#ranking).

A **regex literal** or a **list of keys** scans the annotations with a case-insensitive regular expression instead,
for parts of words and patterns:

    text =~ /fail(over|back)/i                       # regex literal with flags
    text =~ /ailove/                                 # part of a word (a full-text search finds whole words)
    text(architecture/description) =~ "standby"      # only this annotation
    text(link/*, page/content) =~ "PROJ-1234"        # several keys, `*` is any run of characters

In a quoted string a backslash only escapes the next character (`"\d"` is `d`); write patterns with escapes as `/regex/`.

A resource matches the scan when one of the checked annotations matches. The MCP `query` tool shows the annotation
and a short snippet around the match for each hit (`matched_text`), for full-text searches too. The bare word `text`
is still a name search; text in YAML comments is not searched.

### Ranking

A query that searches text (the words of the search box, `text: "..."`) lists its hits by relevance: how often and
where the words occur (a word in the name or title counts ten times a word in the body, rare words more than common
ones), times the weight of the kind. Pages count most, then application services and components, interfaces, the
other layers and technology; settings such as Config and PageMenu least:

| Weight | Kinds |
|--------|-------|
| 3 | `Page` |
| 2 | `ApplicationService`, `ApplicationComponent` |
| 1.5 | `ApplicationInterface` and the rest of the application layer |
| 1.2 | business, strategy and motivation layer |
| 1 | technology and implementation layer |
| 0.5 | other kinds (Config, PageMenu, Grouping, ...) |

A [Config](/kinds/Config) of type `search` named `default` changes them, per layer or per kind (numbers from 0 to
100, the kind before the layer):

```yaml
apiVersion: architecture/v1alpha1
kind: Config
metadata:
  name: default
  annotations:
    config/type: search
    search/weight-technology: "0.8"
    search/weight-TechnologyService: "1.5"
```

Queries without a text search list their hits by name.

## Kind Filter

Prefix your query with `Kind:` to filter by resource type (a capitalised word that is a kind, followed by a space or
nothing; `Kind:Name` without a space is the kind and a name):

    TechnologyArtifact:                              # all of this kind
    TechnologyArtifact: activity/status == "active"  # filtered
    ApplicationComponent: kubernetes          # combined

You can also query the kind field directly using operators:

    kind == "TechnologyArtifact"                                    # exact kind match
    kind =~ "Application.*"                                          # regex match on kind
    kind in ("TechnologyArtifact", "ApplicationComponent")          # kind is one of list

## Annotation Queries

Query annotation values using comparison operators:

| Operator | Description |
|----------|-------------|
| `==` | Equals (numeric comparison for numbers) |
| `!=` | Not equals (numeric comparison for numbers) |
| `=~` | Regex match |
| `>` | Greater than |
| `<` | Less than |
| `>=` | Greater or equal |
| `<=` | Less or equal |
| `in` | Value is one of several options |

Examples:

    activity/status == "active"
    activity/status != "abandoned"
    scc/language/Go/loc > 10000
    scc/language/Go/loc == 15000    # exact numeric match
    repository/artifacts =~ "container|chart"
    repository/artifacts in ("container", "chart")  # matches any listed value

### Quoted Annotation Paths

Use single quotes for annotation paths containing special characters (like `+`):

    'scc/language/C++/loc' >= 500
    'scc/language/C++/loc'?
    activity/status == "active" & 'scc/language/C++ Header/loc' > 100

## Attribute Existence

Check if an annotation is set (exists) or not set (doesn't exist) using `?`:

    activity/status?              # annotation exists
    ! activity/status?            # annotation doesn't exist
    scc/language/Go/loc?          # has Go code metrics

Combined examples:

    activity/status? & ! backup/mode?    # has status but no backup
    TechnologyArtifact: ! activity/status?  # artifacts without status set

## Logical Operators

Combine conditions with logical operators:

| Operator | Aliases |
|----------|---------|
| AND | `&` or `and` or `AND` |
| OR | pipe or `or` or `OR` |
| NOT | `!` or `not` or `NOT` |

Examples:

    activity/status == "active" & repository/artifacts == "container"
    repository/artifacts == "container" | repository/artifacts == "chart"
    ! activity/status == "abandoned"
    (a == "1" | b == "2") & c == "3"

Precedence (highest to lowest): Parentheses, NOT, AND, OR

## Relation Queries

Find resources by their relationships:

| Syntax | Description |
|--------|-------------|
| `-> Kind` | Has direct outgoing relation to kind |
| `-> "Name"` | Has direct outgoing relation to instance |
| `<- Kind` | Has direct incoming relation from kind |
| `~>` | Transitive outgoing (follows chain) |
| `<~` | Transitive incoming (follows chain) |
| `-> none` | Has no outgoing relations |
| `<- none` | Has no incoming relations |

Examples:

    -> ApplicationInterface              # exposes an interface
    -> "Kubernetes:RestAPI"              # exposes specific interface
    <- ApplicationComponent              # referenced by a component
    ~> MotivationRequirement               # transitively reaches requirement
    -> none & <- none                    # orphan (no relations)
    TechnologyArtifact: <- none          # unreferenced artifacts

### Verb Filters

Filter relations by their verb (relation type) using `{verb}` syntax:

**Include verbs (allowlist):**

| Syntax | Description |
|--------|-------------|
| `-{verb}>` | Outgoing direct, only follow 'verb' relations |
| `~{verb}>` | Outgoing transitive, only follow 'verb' relations |
| `<{verb}-` | Incoming direct, only from 'verb' relations |
| `<{verb}~` | Incoming transitive, only from 'verb' relations |
| `-{v1,v2}>` | Multiple verbs (OR semantics - follow v1 OR v2) |

**Exclude verbs (denylist):**

| Syntax | Description |
|--------|-------------|
| `-{!verb}>` | Outgoing direct, follow all EXCEPT 'verb' |
| `~{!verb}>` | Outgoing transitive, follow all EXCEPT 'verb' |
| `<{!verb}-` | Incoming direct, all EXCEPT 'verb' |
| `<{!verb}~` | Incoming transitive, all EXCEPT 'verb' |
| `-{!v1,v2}>` | Exclude multiple verbs (exclude v1 AND v2) |

Examples:

    # Only repos MAINTAINED by team (not contributed)
    TechnologyArtifact: -{maintainedBy}> "MyTeam:Team"

    # All relations EXCEPT contributedBy
    TechnologyArtifact: -{!contributedBy}> "MyTeam:Team"

    # Include multiple verbs
    TechnologyArtifact: -{maintainedBy,contributedBy}> BusinessActor

    # Exclude multiple verbs
    TechnologyArtifact: -{!contributedBy,servedBy}> "MyTeam:Team"

    # Transitive with verb filter
    ApplicationComponent: ~{realizedThrough}> TechnologyArtifact

    # Incoming with verb filter
    BusinessActor: <{maintainedBy}- TechnologyArtifact

    # Combined with sub-queries
    TechnologyArtifact: -{maintainedBy}> $(BusinessActor: activity/status == "active")

    # Find artifacts with NO maintainedBy relations
    TechnologyArtifact: -{maintainedBy}> none

    # Pages that mention a component, and the components they depict
    ApplicationComponent: <{mentions}- Page
    Page: -{depicts}> ApplicationComponent

    # Leave the derived relations (links in text, nodes of diagrams) out of a traversal
    ApplicationComponent: ~{!mentions,depicts}> TechnologyArtifact

## Sub-Query Targets

Use `$(expression)` to dynamically find relation targets based on a query:

| Syntax | Description |
|--------|-------------|
| `-> $(expr)` | Has relation to any resource matching expr |
| `~> $(expr)` | Transitively reaches any resource matching expr |
| `<- $(expr)` | Has incoming relation from any resource matching expr |
| `<~ $(expr)` | Transitively reached by any resource matching expr |

Examples:

    -> $(kubernetes)                     # relates to something named "kubernetes"
    ~> $(name == "MyAPI")                # transitively reaches the instance "MyAPI"
    <- $(TechnologyArtifact: activity/status == "active")  # referenced by active artifacts
    ~> $(-> $(foo))                      # nested: reaches something that reaches "foo"

Sub-queries support the full query syntax including kind filters and logical operators.

## Searching Wiki Pages

[Wiki pages](/doc/pages) are resources of the kind `Page`, so everything above applies. Use the `Page:` prefix
to search pages only.

| Annotation | Content |
|------------|---------|
| `page/title` | Title (the name is the file name, so it is often less readable) |
| `page/tags` | Comma-separated tags |
| `page/status` | Free text such as `rfc`, `wip`, `approved` |
| `page/author`, `page/owner` | `Name <email>` |
| `page/content` | The markdown body, without the frontmatter |

Words typed in the Pages tab search the name, title and text of pages (`Page: handbook`), ranked. In a query, search
the text of pages with `text:` or match `page/content`:

    Page: text: "asd"                                             # pages that mention "asd", best first
    Page: text: "asd" & page/status == "approved"                 # text search plus a filter
    Page: page/content =~ "asd"                                   # a regex on the markdown
    Page: page/tags == "howto"                                    # by tag
    Page: page/content =~ "```asd"                                # pages that contain a diagram

Regular expressions are case-insensitive. Inside a quoted string a backslash escapes the next character and is
dropped, so a regex backslash has to be written twice. That is how a literal `[` is matched, for example to
find the pages that link to a page (backlinks):

    Page: page/content =~ "\\[\\[Writing Pages"                      # pages containing a link to "Writing Pages"

More ways to find pages:

    Page: name == "home"          # the home page
    PageMenu: <- none             # root menus (menus no other menu contains)
    Page: <- none                 # pages that are in no menu (the home page usually is)
    PageMenu: -> Page             # menus that contain pages

Over MCP the same queries work with the `query` tool, see
[Pages and AI assistants](/doc/pages#pages-and-ai-assistants-mcp).

## Examples

Active containerized services:

    TechnologyArtifact: activity/status == "active" & repository/artifacts == "container"

Everything that is on its way out:

    lifecycle/status in ("deprecated", "sunset", "end-of-life")

Resources in use (a resource without a status is active, the annotation's default):

    lifecycle/status == "active"

What is planned, not yet in use:

    lifecycle/status == "planned"

Services exposing APIs:

    ApplicationComponent: -> ApplicationInterface

Large Go codebases:

    TechnologyArtifact: scc/language/Go/loc > 5000

Resources with compliance chain:

    ~> MotivationRequirement

Complex query with grouping:

    (repository/artifacts == "container" | repository/artifacts == "chart") & activity/status == "active"

Using `in` to simplify OR conditions:

    # These two queries are equivalent:
    repository/artifacts == "container" | repository/artifacts == "chart"
    repository/artifacts in ("container", "chart")

    # Combined with other conditions:
    activity/status == "active" & repository/artifacts in ("container", "chart")

## Search results

The result page lists the hits with a count per kind. Click a kind to narrow the list; the query stays the same.
Every hit also shows its **summary attributes**: up to three annotations per kind (normal or computed) that
the kind definition marks with `summary: true`, for example the activity status of a repository or the priority
of a requirement. Clicking a tag value searches for that value.

The same data is available from the API: `GET /api/v1/search?q=...` returns `by_kind` (hits per kind, for all
hits of the query) and, for each hit, `highlights`:

    "highlights": [
      { "key": "activity/status", "title": "Activity Status", "value": "active", "format": "tag_word", "type": null }
    ]

Add `kind=TechnologyArtifact` to narrow the hits to one kind (`total` and paging follow, `by_kind` still counts
all hits).

### Hits of a text search

When the query searches text (words in the search box, `text: "..."`, `text =~ /.../`), every hit shows where the
words occur: its title with the words marked, and up to two **excerpts** from the fields with the most of the
searched words (a description before a tag list), cut to the part that holds most of them, markdown taken off.
Word forms are marked too (a search for `failovers` marks *Failover*). The hits come best match first; **Name**
next to the result count lists them alphabetically instead.

In the API (`fulltext=true` for the search box words, `sort=name` for the name order) such hits carry:

    "title": "Diagrams in Pages",
    "title_marks": [[0, 8]],
    "relevance": 0.674,
    "matches": [
      { "key": "page/content", "title": "Content",
        "text": "…They render to inline SVG, need no external tool…", "marks": [[5, 11]] }
    ]

`marks` are `[from, to)` ranges of characters (code points) in `text`; `relevance` is relative to the best hit
(1.0), only when the hits are ranked. The response says `"sort": "relevance"` or `"name"`, and `"ranked": true`
when the query searches text. The MCP `query` tool shows the same excerpts as `matched_text`.
