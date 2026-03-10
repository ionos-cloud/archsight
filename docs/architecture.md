# Architecture

## Technology Stack

- **Backend**: Sinatra (REST API)
- **Frontend**: Vue 3 + Vue Router 4
- **Build Tool**: Vite
- **Styling**: Pico CSS v2.x
- **Icons**: Iconoir
- **Visualization**: GraphViz (@hpcc-js/wasm, client-side)
- **Editor**: Lexical

## Directory Structure

```text
archsight/
├── exe/archsight              # CLI executable
├── frontend/                  # Vue 3 SPA
│   ├── src/
│   │   ├── components/        # Vue components (40+)
│   │   ├── composables/       # Reusable composables
│   │   ├── router/            # Vue Router config
│   │   └── css/               # Styles
│   └── vite.config.js         # Vite build config
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
│       └── web/               # Sinatra API + static file serving
│           └── doc/           # Documentation (markdown)
├── docs/                      # Project documentation
└── test/                      # Test suite
```
