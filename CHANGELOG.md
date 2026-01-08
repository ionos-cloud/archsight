## [Unreleased]

## [0.1.0] - 2026-01-07

Initial release. Extracted from internal architecture tooling.

### Features

- **Resource Modeling**: 20+ ArchiMate-inspired resource types (TechnologyArtifact, ApplicationComponent, ApplicationInterface, BusinessRequirement, etc.)
- **Query Language**: Full-featured query DSL with operators (==, !=, =~, >, <), relation queries (->/<-/~>/<~), logical operators (AND/OR/NOT), and sub-queries
- **Web Interface**: Browse, search, and visualize architecture resources with interactive GraphViz diagrams
- **MCP Server**: AI assistant integration via Model Context Protocol with query, analyze_resource, and resource_doc tools
- **Computed Annotations**: Aggregate values across resource relations (sum, count, min, max, avg, concat)
- **Validation (Lint)**: YAML syntax checking, resource kind validation, relation reference verification
- **Template Generation**: Generate YAML templates for any resource type
- **Docker Support**: Production-ready container with health checks
- **Dark Mode**: Full dark mode support in web interface

### Documentation

- Modeling guide with resource types and relations
- Query language reference
- Computed annotations guide
- ArchiMate and TOGAF alignment documentation
