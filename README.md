# Archsight

[![CI](https://github.com/ionos-cloud/archsight/actions/workflows/ci.yml/badge.svg)](https://github.com/ionos-cloud/archsight/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/archsight.svg)](https://badge.fury.io/rb/archsight)

*Bringing enterprise architecture into focus.*

Ruby gem for visualizing and managing enterprise architecture documentation using YAML resources with GraphViz visualization. Inspired by ArchiMate 3.2.

## Installation

Add to your Gemfile:

```ruby
gem 'archsight'
```

Or install directly:

```bash
gem install archsight
```

### Option 2: Helm (Kubernetes)

```bash
helm install archsight oci://ghcr.io/ionos-cloud/archsight/charts/archsight
```

## Quick Start

### Option 1: CLI

```bash
# Start web server (looks for resources in current directory)
archsight web

# Start with custom resources path
archsight web --resources /path/to/resources

# Or use environment variable
ARCHSIGHT_RESOURCES_DIR=/path/to/resources archsight web
```

Access at: <http://localhost:4567>

### Option 2: Docker

```bash
# Run web server (default)
docker run -p 4567:4567 -v "/path/to/resources:/resources" ghcr.io/ionos-cloud/archsight

# Run in production mode with logging
docker run -p 4567:4567 -v "/path/to/resources:/resources" ghcr.io/ionos-cloud/archsight web --production

# Run lint
docker run -v "/path/to/resources:/resources" ghcr.io/ionos-cloud/archsight lint -r /resources

# Run any command
docker run ghcr.io/ionos-cloud/archsight version
```

Access web interface at: <http://localhost:4567>

**Notes:**

- Volume mount `-v "/path/to/resources:/resources"` mounts your resources directory
- Default command starts the web server on port 4567
- Pass subcommands directly (lint, version, console, template)

## CLI Commands

```bash
archsight web [OPTIONS]      # Start web server
archsight lint               # Validate YAML and relations
archsight import             # Execute pending imports
archsight analyze            # Execute analysis scripts
archsight template KIND      # Generate YAML template for a resource type
archsight console            # Interactive Ruby console
archsight version            # Show version
```

### Web Server Options

```bash
archsight web [--resources PATH] [--port PORT] [--host HOST]
              [--production] [--disable-reload] [--enable-logging]
```

| Option | Description |
|--------|-------------|
| `-r, --resources PATH` | Path to resources directory |
| `-p, --port PORT` | Port to listen on (default: 4567) |
| `-H, --host HOST` | Host to bind to (default: localhost) |
| `--production` | Run in production mode (quiet startup) |
| `--disable-reload` | Disable the reload button in the UI |
| `--enable-logging` | Enable request logging (default: false in dev, true in prod) |

## Features

### MCP Server

The tool includes an MCP (Model Context Protocol) server that enables AI assistants to query and analyze the architecture data programmatically.

**Start the server:**

```bash
archsight web
```

**Add to Claude Code:**

```bash
claude mcp add --transport sse ionos-architecture http://localhost:4567/mcp/sse
```

**Available tools:**

- `query` - Search and filter resources using the query language
- `analyze_resource` - Get detailed resource information and impact analysis
- `resource_doc` - Get documentation for resource kinds

### Web Interface

**Browse & Search:**

- Browse resources by type (Products, Services, Components, Requirements, etc.)
- Search by name or tag using the [query language](lib/archsight/web/doc/search.md)
- Filter by annotations (quality attributes, status, frameworks)

**Visualization:**

- Interactive GraphViz diagrams showing relationships
- Zoom/pan controls for large diagrams
- Dark mode support
- Layer-based color scheme (Business, Application, Technology, Data)

### Validation

Validate YAML syntax and verify all relationship references:

```bash
archsight lint
```

**Checks:**

- YAML syntax correctness
- Resource kind definitions exist
- All relation references point to existing resources
- Prevents broken links between resources

## Documentation

Detailed documentation is available in the web interface under the Help menu:

| Guide | Description |
|-------|-------------|
| [Modeling Guide](lib/archsight/web/doc/modeling.md) | How to model architecture using resource types and relations |
| [Query Language](lib/archsight/web/doc/search.md) | Full query syntax reference for searching resources |
| [Computed Annotations](lib/archsight/web/doc/computed_annotations.md) | Aggregating values across relations |
| [ArchiMate Reference](lib/archsight/web/doc/archimate.md) | ArchiMate concepts and mapping |
| [TOGAF Reference](lib/archsight/web/doc/togaf.md) | TOGAF alignment and concepts |

## Architecture

### Technology Stack

- **Web Framework**: Sinatra
- **Templating**: Haml
- **Styling**: Pico CSS v2.x
- **Interactivity**: HTMX
- **Icons**: Iconoir (1,671+ icons)
- **Visualization**: GraphViz (@hpcc-js/wasm for client-side SVG)

### Directory Structure

```text
archsight/
├── exe/archsight              # CLI executable
├── lib/
│   ├── archsight.rb           # Entry point
│   └── archsight/
│       ├── cli.rb             # Thor CLI
│       ├── configuration.rb   # Resources path config
│       ├── database.rb        # YAML loader and validator
│       ├── query/             # Query language (lexer, parser, evaluator)
│       ├── resources/         # Resource types (20+)
│       ├── annotations/       # Annotation modules
│       ├── mcp/               # MCP server tools
│       └── web/               # Sinatra app, views, assets
│           └── doc/           # Documentation (markdown)
└── test/                      # Test suite
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, code style guidelines, and pull request process.

## License

Apache 2.0 License. See LICENSE.txt for details.
