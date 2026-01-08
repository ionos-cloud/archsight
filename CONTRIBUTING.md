# Contributing to Archsight

Thank you for your interest in contributing to Archsight! This guide will help you get started.

## Development Setup

### Prerequisites

- Ruby 3.4 or later
- Bundler
- GraphViz (for visualization features)

### Installation

```bash
git clone https://github.com/ionos-cloud/archsight.git
cd archsight
bundle install
```

### Running Locally

```bash
# Run tests
bundle exec rake test

# Start web server with example data
./exe/archsight web --resources examples/archsight

# Lint example resources
./exe/archsight lint --resources examples/archsight

# Generate a resource template
./exe/archsight template ApplicationComponent

# Interactive console
./exe/archsight console --resources examples/archsight
```

### Type Checking

The project uses RBS type definitions with Steep:

```bash
bundle exec steep check
```

### Linting

```bash
bundle exec rubocop
```

### Code Coverage

After running tests, coverage reports are generated in the `coverage/` directory:

```bash
bundle exec rake test
open coverage/index.html  # View HTML report
```

Coverage is grouped by component: Core, Query, Resources, Annotations, MCP, and Web.

## Code Style and Conventions

### Ruby Style

- Follow the RuboCop configuration in `.rubocop.yml`
- Use compact class/module definitions: `class Archsight::Query::Lexer` instead of nested modules
- Prefer single-line class definitions where the parent namespace is already defined

### Resource Types

When adding new resource types:

```ruby
class Archsight::Resources::MyResource < Archsight::Resources::Base
  include_annotations :git, :architecture, :generated

  icon 'box'  # Iconoir icon name

  annotation 'custom/field',
    description: 'Custom field description',
    enum: ['value1', 'value2']

  relation :realizes, :businessRequirements, :BusinessRequirement
end
```

### Annotations

- Use namespaced paths: `category/field` (e.g., `activity/status`, `repository/git`)
- Provide descriptions for all annotations
- Use `enum` for fields with fixed values
- Use `computed` for aggregated values

### Tests

- Add tests for new features in the `test/` directory
- Use Minitest with the existing test helpers
- The `MockDatabase` helper is available for unit tests
- Example resources in `examples/archsight/` can be used for integration tests

## Pull Request Process

1. **Fork and Branch**: Create a feature branch from `main`

   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make Changes**: Implement your feature or fix

3. **Test**: Ensure all tests pass

   ```bash
   bundle exec rake test
   bundle exec rubocop
   bundle exec steep check
   ```

4. **Commit**: Write clear commit messages

   ```text
   Add support for new annotation type

   - Added category/field annotation to ResourceType
   - Updated documentation
   - Added tests for new functionality
   ```

5. **Push and PR**: Open a pull request against `main`
   - Describe what the PR does
   - Reference any related issues
   - Include test coverage for new features

## Issue Reporting Guidelines

### Bug Reports

Include:

- Ruby version (`ruby -v`)
- Archsight version
- Steps to reproduce
- Expected vs actual behavior
- Relevant YAML resource files (if applicable)

### Feature Requests

Include:

- Use case description
- Proposed solution (if any)
- Examples of how the feature would be used

## Project Structure

```text
archsight/
├── exe/archsight              # CLI executable
├── lib/
│   ├── archsight.rb           # Entry point
│   └── archsight/
│       ├── cli.rb             # Thor CLI commands
│       ├── configuration.rb   # Configuration management
│       ├── database.rb        # YAML loader and resource registry
│       ├── query/             # Query language implementation
│       │   ├── lexer.rb       # Tokenizer
│       │   ├── parser.rb      # AST builder
│       │   └── evaluator.rb   # Query execution
│       ├── resources/         # Resource type definitions
│       ├── annotations/       # Annotation modules
│       ├── mcp/               # MCP server implementation
│       └── web/               # Sinatra web application
│           ├── doc/           # Documentation (markdown)
│           └── views/         # Haml templates
├── examples/archsight/        # Self-documenting example resources
├── sig/                       # RBS type definitions
└── test/                      # Test suite
```

## Questions?

Open an issue on GitHub: <https://github.com/ionos-cloud/archsight/issues>
