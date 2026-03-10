# Computed Annotations

Computed annotations are dynamic values calculated from related resources at database load time. Unlike regular annotations that are stored in YAML files, computed annotations are derived from the data of related resources in the resource graph.

## Overview

Computed annotations allow you to:

- **Aggregate data** from related resources (sum, count, average, etc.)
- **Collect information** across the resource tree (unique languages, all tags, etc.)
- **Compute derived metrics** (risk scores, costs, coverage percentages)

They are computed after all resources are loaded and relations are resolved, making the full resource graph available for computation.

## Defining Computed Annotations

Computed annotations are defined in resource classes using the `computed_annotation` DSL:

```ruby
class ApplicationComponent < Base
  computed_annotation 'computed/artifact_count',
                      title: 'Artifact Count',
                      description: 'Number of related technology artifacts' do
    count(outgoing_transitive(:TechnologyArtifact))
  end
end
```

### DSL Options

Computed annotations support all the same options as regular annotations:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `key` | String | required | The annotation key (first argument) |
| `description` | String | nil | Human-readable description |
| `title` | String | nil | Display title for UI |
| `filter` | Symbol | nil | Filter type (`:word`, `:list`) |
| `format` | Symbol | nil | Rendering format (`:markdown`, `:tag_word`, `:tag_list`) |
| `enum` | Array | nil | Allowed values |
| `sidebar` | Boolean | false | Show in sidebar |
| `type` | Class | nil | Type for value coercion (Integer, Float, String) |
| `list` | Boolean | false | Whether values are lists |
| `&block` | Block | required | The computation logic |

### Value Handling

- **Nil values**: Not stored (annotation key won't exist)
- **Empty arrays**: Not stored (annotation key won't exist)
- **Arrays**: Converted to comma-separated strings for storage
- **Other values**: Stored as-is (with optional type coercion)

### Example Definitions

```ruby
# Count related resources
computed_annotation 'computed/artifact_count',
                    title: 'Artifact Count',
                    description: 'Number of related technology artifacts' do
  count(outgoing_transitive(:TechnologyArtifact))
end

# Sum numeric values with type coercion
computed_annotation 'computed/total_cost',
                    title: 'Total Cost',
                    description: 'Total estimated cost',
                    type: Integer do
  sum(outgoing_transitive(:TechnologyArtifact), 'scc/estimatedCost')
end

# Find primary language (by LOC)
computed_annotation 'computed/primary_language',
                    title: 'Primary Language',
                    description: 'Programming language with most lines of code',
                    filter: :word do
  artifacts = outgoing_transitive(:TechnologyArtifact)
  loc_by_language = Hash.new(0)
  artifacts.each do |artifact|
    artifact.annotations.each do |key, value|
      if key =~ %r{^scc/language/(.+)/loc$}
        loc_by_language[Regexp.last_match(1)] += value.to_i
      end
    end
  end
  loc_by_language.max_by { |_, loc| loc }&.first
end

# Collect unique values (stored as comma-separated string)
computed_annotation 'computed/languages',
                    title: 'Languages',
                    description: 'All programming languages used',
                    filter: :list,
                    list: true do
  collect(outgoing_transitive(:TechnologyArtifact), 'scc/languages')
end
```

## Relation Traversal Methods

Inside the computation block, you have access to relation traversal methods:

| Method | Query Equivalent | Description |
|--------|------------------|-------------|
| `outgoing(Kind)` | `-> Kind` | Direct outgoing relations to specified kind |
| `outgoing_transitive(Kind)` | `~> Kind` | All transitively reachable resources of kind |
| `incoming(Kind)` | `<- Kind` | Direct incoming relations from specified kind |
| `incoming_transitive(Kind)` | `<~ Kind` | All resources that transitively reference this one |

### Filter Parameter

All relation methods accept either:
- **Symbol**: Simple kind filter (e.g., `:TechnologyArtifact`)
- **String**: Full query selector using the query language (e.g., `'TechnologyArtifact: activity/status == "active"'`)

### Examples

```ruby
# Direct relations only
outgoing(:TechnologyArtifact)  # Resources directly related

# Transitive relations (follows relation chains)
outgoing_transitive(:TechnologyArtifact)  # All reachable artifacts

# Incoming relations
incoming(:ApplicationService)  # Services that reference this component

# With depth limit
outgoing_transitive(:TechnologyArtifact, max_depth: 5)

# Query selector - filter by annotation value
outgoing_transitive('TechnologyArtifact: activity/status == "active"')

# Query selector - filter by numeric comparison
outgoing('TechnologyArtifact: scc/estimatedCost > 10000')

# Query selector - filter by name pattern
outgoing_transitive('TechnologyArtifact: name =~ "repo-go"')

# Query selector - kind filter only
incoming_transitive('ApplicationService:')
```

## Aggregation Functions

The following aggregation functions are available:

### Numeric Aggregations

| Function | Description | Returns |
|----------|-------------|---------|
| `sum(instances, key)` | Sum of numeric annotation values | Float or nil |
| `avg(instances, key)` | Average of numeric values | Float or nil |
| `min(instances, key)` | Minimum numeric value | Float or nil |
| `max(instances, key)` | Maximum numeric value | Float or nil |

### Counting

| Function | Description | Returns |
|----------|-------------|---------|
| `count(instances)` | Count of instances | Integer |
| `count(instances, key)` | Count of non-nil annotation values | Integer |

### Collection

| Function | Description | Returns |
|----------|-------------|---------|
| `collect(instances, key)` | Unique sorted values | Array |
| `first(instances, key)` | First non-nil value | Any or nil |
| `most_common(instances, key)` | Most frequent value (mode) | Any or nil |

### Usage Examples

```ruby
# Sum estimated costs
sum(outgoing_transitive(:TechnologyArtifact), 'scc/estimatedCost')

# Count artifacts with specific status
count(outgoing_transitive(:TechnologyArtifact), 'activity/status')

# Average lines of code
avg(outgoing_transitive(:TechnologyArtifact), 'scc/loc')

# Get all unique languages
collect(outgoing_transitive(:TechnologyArtifact), 'scc/languages')

# Find primary language
most_common(outgoing_transitive(:TechnologyArtifact), 'scc/languages')
```

## Accessing Other Annotations

Inside the computation block, you can access:

### Regular Annotations

```ruby
computed_annotation 'computed/risk_adjusted_cost' do
  base_cost = sum(outgoing_transitive(:TechnologyArtifact), 'scc/estimatedCost')
  risk_factor = annotation('risk/factor')&.to_f || 1.0
  base_cost * risk_factor if base_cost
end
```

### Other Computed Annotations

```ruby
computed_annotation 'computed/cost_per_artifact' do
  total = computed('computed/total_cost')
  count = computed('computed/artifact_count')
  total / count if total && count && count > 0
end
```

## Execution Order

1. Database loads all YAML resources
2. Relations are verified and resolved
3. Computed annotations are calculated for all instances
4. Values are cached for performance

Computed annotations that depend on other computed annotations are resolved automatically through lazy evaluation with cycle detection.

## Querying Computed Values

Computed annotations are written to the instance's annotation hash, making them queryable like regular annotations:

```ruby
# Using the query language
db.query('ApplicationComponent: computed/artifact_count > 10')

# Direct access
instance.annotations['computed/artifact_count']

# Via the dedicated method
instance.computed_annotation_value('computed/artifact_count')
```

## Best Practices

### Naming Convention

Use the `computed/` prefix for computed annotation keys to distinguish them from stored annotations:

```ruby
computed_annotation 'computed/total_cost' do
  # ...
end
```

### Performance Considerations

- Computed values are cached after first calculation
- Avoid deep transitive traversals when possible (use `max_depth`)
- Consider the number of related resources when designing aggregations

### Error Handling

- Aggregation functions handle nil values gracefully
- Empty result sets return nil for most aggregations
- Circular dependencies are detected and raise an error

## Complete Example

```ruby
class ApplicationComponent < Base
  # Count related artifacts
  computed_annotation 'computed/artifact_count',
                      title: 'Artifact Count',
                      description: 'Number of related technology artifacts' do
    count(outgoing_transitive(:TechnologyArtifact))
  end

  # Sum costs with type coercion
  computed_annotation 'computed/total_cost',
                      title: 'Total Cost',
                      description: 'Total estimated cost from related artifacts',
                      type: Integer do
    sum(outgoing_transitive(:TechnologyArtifact), 'scc/estimatedCost')
  end

  # Find primary language by LOC
  computed_annotation 'computed/primary_language',
                      title: 'Primary Language',
                      description: 'Programming language with most lines of code',
                      filter: :word do
    artifacts = outgoing_transitive(:TechnologyArtifact)
    loc_by_language = Hash.new(0)
    artifacts.each do |artifact|
      artifact.annotations.each do |key, value|
        if key =~ %r{^scc/language/(.+)/loc$}
          loc_by_language[Regexp.last_match(1)] += value.to_i
        end
      end
    end
    loc_by_language.max_by { |_, loc| loc }&.first
  end

  # Collect all languages (stored as comma-separated string)
  computed_annotation 'computed/languages',
                      title: 'Languages',
                      description: 'All programming languages used across related artifacts',
                      filter: :list,
                      list: true do
    collect(outgoing_transitive(:TechnologyArtifact), 'scc/languages')
  end

  # Derived computation using other computed values
  computed_annotation 'computed/avg_cost_per_artifact',
                      title: 'Avg Cost per Artifact',
                      description: 'Average cost per artifact' do
    total = computed('computed/total_cost')
    count = computed('computed/artifact_count')
    (total.to_f / count).round(2) if total && count && count > 0
  end
end
```
