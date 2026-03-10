# Query Syntax

The search box supports a powerful query language for filtering architecture resources.

## Quick Start

| Query | Description |
|-------|-------------|
| `kubernetes` | Name contains "kubernetes" (case-insensitive) |
| `TechnologyArtifact:` | All resources of a specific kind |
| `activity/status == "active"` | Annotation equals value |
| `scc/loc == 15000` | Numeric equality |
| `activity/status?` | Annotation exists (is set) |
| `! activity/status?` | Annotation doesn't exist |
| `-> ApplicationInterface` | Has relation to a kind |

## Name Search

Type any word to search by name (case-insensitive regex match):

    kubernetes              # name =~ "kubernetes"
    name == "MyService"     # exact match
    name =~ "repo-.*"       # regex pattern
    name != "OldService"    # not equal
    name in ("a", "b")      # name is one of several options

## Kind Filter

Prefix your query with `Kind:` to filter by resource type:

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
    ~> BusinessRequirement               # transitively reaches requirement
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

## Examples

Active containerized services:

    TechnologyArtifact: activity/status == "active" & repository/artifacts == "container"

Services exposing APIs:

    ApplicationComponent: -> ApplicationInterface

Large Go codebases:

    TechnologyArtifact: scc/language/Go/loc > 5000

Resources with compliance chain:

    ~> BusinessRequirement

Complex query with grouping:

    (repository/artifacts == "container" | repository/artifacts == "chart") & activity/status == "active"

Using `in` to simplify OR conditions:

    # These two queries are equivalent:
    repository/artifacts == "container" | repository/artifacts == "chart"
    repository/artifacts in ("container", "chart")

    # Combined with other conditions:
    activity/status == "active" & repository/artifacts in ("container", "chart")
