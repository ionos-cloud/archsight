# Import System

The import system allows you to declaratively define data imports that generate architecture resources from external sources like GitLab, GitHub, and git repositories.

## Overview

Imports are defined as YAML resources with kind `Import`. Each import specifies:

- A **handler** that knows how to fetch and process data
- **Configuration** specific to that handler
- **Dependencies** on other imports that must complete first
- Optional **caching** to avoid re-running unchanged imports

The import executor runs imports concurrently in dependency order, with a visual progress display showing completion percentage and ETA.

## Running Imports

```bash
# Run all pending imports
archsight import

# Verbose output
archsight import -v

# Show execution plan without running
archsight import --dry-run
```

### Progress Display

In TTY mode, imports show a live progress display:

```
Overall ████████████░░░░░░░░ 60% [30/50] ETA: 2:15
Import:Repo:project-a - Analyzing code
Import:Repo:project-b - Cloning repository
Import:Repo:project-c - Done
```

## Defining an Import

Create YAML files in the `imports/` directory:

```yaml
apiVersion: architecture/v1alpha1
kind: Import
metadata:
  name: Import:MyData
  annotations:
    import/handler: <handler-name>
    import/priority: "10"
    import/cacheTime: "24h"
    import/config/key: value
spec:
  dependsOn:
    imports:
      - Import:Dependency
```

### Core Annotations

| Annotation | Description |
|------------|-------------|
| `import/handler` | Handler to execute (required) |
| `import/enabled` | Set to "false" to disable |
| `import/priority` | Execution order (lower runs first, default: 0) |
| `import/cacheTime` | Cache duration: "30m", "1h", "24h", "7d", or "never" |
| `import/outputPath` | Output file path relative to resources directory |

### Caching

Imports can be cached to avoid re-running when data hasn't changed:

```yaml
import/cacheTime: "24h"  # Re-run after 24 hours
```

Supported duration formats:
- `30m` - 30 minutes
- `1h` - 1 hour
- `24h` - 24 hours
- `7d` - 7 days
- `never` - Always run (default)

The cache uses the `generated/at` annotation written by handlers. When an import completes, it writes a marker with the current timestamp. On subsequent runs, the executor checks if `generated/at + cacheTime > now` to skip cached imports.

### Configuration Pattern

Handler-specific configuration uses `import/config/*` annotations:

```yaml
import/config/host: gitlab.company.com
import/config/fallbackTeam: "Team:Platform"
```

## Available Handlers

### gitlab

Lists repositories from a GitLab instance and generates child Import resources.

**Configuration:**
- `host` - GitLab host (required)
- `exploreGroups` - If "true", explore all visible groups (default: false)
- `repoOutputPath` - Output path for repository handler results
- `fallbackTeam` - Default team when no contributor match found
- `botTeam` - Team for bot-only repositories

**Environment:**
- `GITLAB_TOKEN` - Personal access token (required)

**Output:** Generates `Import:Repo:gitlab:*` resources for each repository.

### github

Lists repositories from a GitHub organization and generates child Import resources.

**Configuration:**
- `org` - GitHub organization (required)
- `repoOutputPath` - Output path for repository handler results

**Environment:**
- `GITHUB_TOKEN` - GitHub Personal Access Token (required)
  - Create at: https://github.com/settings/tokens
  - Required scopes: `repo` (private repos) or `public_repo` (public only)
  - If you have `gh` CLI authenticated: `export GITHUB_TOKEN=$(gh auth token)`

**Output:** Generates `Import:Repo:github:*` resources for each repository.

### repository

Analyzes a single git repository and generates a TechnologyArtifact resource.

**Configuration:**
- `path` - Local repository path (required)
- `gitUrl` - Git URL to clone from (if not already cloned)
- `archived` - If "true", mark as archived
- `visibility` - Repository visibility: internal, public, open-source
- `sccPath` - Path to scc binary (default: scc)
- `fallbackTeam` - Default team when no contributor match found
- `botTeam` - Team for bot-only repositories

**Output:** Generates one TechnologyArtifact resource with:
- Code analysis metrics (languages, LOC, estimated cost)
- Git activity metrics (commits, contributors, bus factor)
- Team matching based on contributor history
- Deployment artifact detection (containers, charts, etc.)
- Agentic tool detection (Claude, Cursor, etc.)

**Special Cases:**

The repository handler creates minimal artifacts for repositories that can't be fully analyzed:

| Status | Reason |
|--------|--------|
| `inaccessible` | Clone failed due to access denied or auth errors |
| `empty` | Repository has no commits |
| `no-code` | No analyzable source code (only config, docs, etc.) |

These artifacts include `activity/status` and `activity/reason` annotations documenting why full analysis wasn't possible.

## Multi-Stage Import Pattern

Imports can generate other Import resources, enabling multi-stage workflows:

1. **GitLab import** runs and discovers repositories
2. Generates `Import:Repo:*` for each repository
3. Database reloads, discovers new Import resources
4. **Repository imports** run concurrently (up to 20)
5. Each generates TechnologyArtifact resources
6. Loop continues until no pending imports remain

### Example: GitLab Multi-Stage Import

```yaml
# imports/gitlab.yaml
apiVersion: architecture/v1alpha1
kind: Import
metadata:
  name: Import:GitLab
  annotations:
    import/handler: gitlab
    import/priority: "1"
    import/cacheTime: "24h"
    import/config/host: gitlab.company.com
    import/config/repoOutputPath: generated/repositories.yaml
    import/config/fallbackTeam: "Team:Platform"
spec: {}
```

After running, this generates:

```yaml
# generated/gitlab-imports.yaml
---
apiVersion: architecture/v1alpha1
kind: Import
metadata:
  name: Import:Repo:gitlab:company:my-service
  annotations:
    import/handler: repository
    import/config/path: ~/.cache/archsight/git/gitlab/company/my-service
    import/config/gitUrl: git@gitlab.company.com:company/my-service.git
    import/config/archived: "false"
    import/config/visibility: internal
    import/outputPath: generated/repositories.yaml
spec:
  dependsOn:
    imports:
      - Import:GitLab
```

## Generated Annotations

### TechnologyArtifact Annotations

Repository analysis generates these annotations:

**Repository Info:**
- `artifact/type` - Always "repo" for repositories
- `repository/git` - Git URL
- `repository/visibility` - internal, public, open-source
- `repository/recentTags` - Recent git tags (releases)
- `repository/accessible` - "false" if repo couldn't be accessed
- `repository/error` - Error message for inaccessible repos

**Code Metrics (from scc):**
- `scc/languages` - Comma-separated language list
- `scc/estimatedCost` - COCOMO cost estimate
- `scc/estimatedPeople` - Estimated team size
- `scc/language/*/loc` - Lines of code per language

**Activity Metrics:**
- `activity/status` - active, abandoned, bot-only, archived, inaccessible, empty, no-code
- `activity/reason` - Explanation for non-standard statuses
- `activity/commits` - Monthly commit counts (12 months)
- `activity/contributors` - Monthly contributor counts
- `activity/contributors/6m` - Unique contributors (6 months)
- `activity/contributors/total` - Total unique contributors
- `activity/busFactor` - Risk assessment: high, medium, low
- `activity/createdAt` - First commit date
- `activity/lastHumanCommit` - Last non-bot commit date

**Deployment Detection:**
- `repository/artifacts` - Detected artifact types (container, chart, debian, rpm)
- `deployment/images` - OCI container image names
- `workflow/platforms` - CI/CD platforms (github-actions, gitlab-ci)
- `workflow/types` - Workflow types (build, test, deploy, etc.)
- `agentic/tools` - AI coding tools detected (claude, cursor, aider)

## Troubleshooting

### Deadlock Error

If you see "Deadlock: pending imports have unsatisfied dependencies", check that:

1. All dependencies exist as Import resources
2. Dependencies don't form a circular chain
3. Dependent imports haven't failed

### Access Denied Errors

When a repository can't be cloned due to access issues, the handler creates a minimal artifact with:
- `activity/status: inaccessible`
- `repository/accessible: false`
- `repository/error: <error message>`

This allows the import to continue processing other repositories.

### Cached Imports Not Updating

If an import isn't re-running when expected:
1. Check `import/cacheTime` annotation value
2. Check `generated/at` annotation on the Import resource
3. Use `import/cacheTime: never` to force re-run

## Creating Custom Handlers

To create a new handler:

1. Create a Ruby file in `lib/archsight/import/handlers/`
2. Inherit from `Archsight::Import::Handler`
3. Implement the `execute` method
4. Register with `Registry.register("name", YourHandler)`

```ruby
# Repository handler - clones/syncs and analyzes a git repository
class Archsight::Import::Handlers::Custom < Archsight::Import::Handler
  def execute
    # Read configuration
    url = config("url")

    # Update progress
    progress.update("Fetching data")

    # Fetch and process data
    data = fetch_data(url)

    # Generate resources
    resources = data.map { |item| build_resource(item) }

    # Write output with self-marker for caching
    yaml_content = resources_to_yaml(resources) + YAML.dump(self_marker)
    write_yaml(yaml_content)
  end

  # Marker for cache timestamp
  def self_marker
    {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => import_resource.name,
        "annotations" => { "generated/at" => Time.now.utc.iso8601 }
      },
      "spec" => {}
    }
  end

  private

  def build_resource(item)
    resource_yaml(
      kind: "TechnologyArtifact",
      name: item["name"],
      annotations: { "custom/field" => item["value"] }
    )
  end
end

Archsight::Import::Registry.register("custom", Archsight::Import::Handlers::Custom)
```

### Handler Helper Methods

| Method | Description |
|--------|-------------|
| `config(key, default:)` | Get configuration value |
| `progress.update(msg)` | Update progress display |
| `write_yaml(content)` | Write YAML to output path |
| `resource_yaml(kind:, name:, ...)` | Build resource hash |
| `import_yaml(name:, handler:, ...)` | Build child import hash |
