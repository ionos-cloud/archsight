# Tool Guide

The Architecture Tool provides a web interface for exploring and managing architecture resources defined in YAML files.

## Navigation

### Home

The home page displays an overview graph of all architecture resources and their relationships. Click on any node to navigate to its detail page.

### Sidebar

The left sidebar lists all resource types (kinds). Click on a kind to see all instances of that type.

### Search

The search box in the navigation bar supports a powerful query language. See [Query Syntax](/doc/search) for details.

Quick examples:

- `kubernetes` - Find resources with "kubernetes" in the name
- `TechnologyArtifact:` - List all technology artifacts
- `activity/status == "active"` - Filter by annotation value

### Help

Click the help icon next to the search box to access this documentation.

### Reload

Click "Reload" to refresh the architecture database from YAML files. Use this after editing resource files.

## Resource Detail View

When viewing a resource, you'll see:

### Header

- Resource name and kind
- Icon representing the resource type

### Annotations

Key-value metadata about the resource. Click on annotation values to filter by that value.

### Relations

Connections to other resources, organized by relation type:

- **Outgoing relations** - What this resource connects to
- **Incoming relations** - What connects to this resource

Click on related resources to navigate to them.

### Graph

A visual representation of the resource and its immediate relationships.

## Views

Views are saved queries with custom display options. Create views to quickly access commonly needed information.

View configuration:

- `view/query` - The search query to execute
- `view/fields` - Comma-separated annotation fields to display as columns
- `view/type` - Display format (`list:name` or `list:name+kind`)
- `view/sort` - Sort order (prefix with `-` for descending)

## YAML Resource Files

Resources are defined in YAML files under the `resources/` directory. Each file contains one or more resource definitions.

Basic structure:

```yaml
kind: TechnologyArtifact
name: my-service
spec:
  description: Service description
annotations:
  activity/status: active
  repository/artifacts: container
relations:
  maintainedBy:
    businessActors:
      - TeamName
```

See [Architecture Modeling](/doc/modeling) for guidance on structuring your architecture.
