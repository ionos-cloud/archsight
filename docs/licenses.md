# License Scanning

The repository import automatically detects and analyzes software licenses for each imported repository. This produces a "Layer 1 Licensing Profile" that characterizes license usage across your portfolio.

## Overview

When the `repository` handler imports a git repository, it runs license analysis alongside code metrics and git history analysis. The license analyzer:

1. **Detects the repository's own license** from LICENSE/COPYING files, SPDX headers, and package manifests
2. **Scans dependency licenses** using language-specific tools (when available) or falls back to manifest-based counting
3. **Classifies risk** based on copyleft presence and unknown license ratios

Results are stored as `license/*` annotations on the TechnologyArtifact resource.

## How License Detection Works

The analyzer uses a priority-based detection strategy:

### 1. SPDX-License-Identifier Headers (highest priority)

Source files are scanned for standardized SPDX headers:

```go
// SPDX-License-Identifier: Apache-2.0
package main
```

This is the most reliable signal and takes priority over all other methods.

### 2. LICENSE / COPYING Files

The analyzer searches for these files in the repository root (in order):

- `LICENSE`, `LICENSE.md`, `LICENSE.txt`
- `LICENCE`, `LICENCE.md`, `LICENCE.txt`
- `COPYING`, `COPYING.md`, `COPYING.txt`

File content is matched against known license patterns for:

| License | Category |
|---------|----------|
| Apache-2.0 | permissive |
| MIT | permissive |
| BSD-3-Clause, BSD-2-Clause | permissive |
| ISC | permissive |
| Unlicense, CC0-1.0, BSL-1.0 | permissive |
| GPL-3.0, GPL-2.0, AGPL-3.0 | copyleft |
| LGPL-3.0, LGPL-2.1 | weak-copyleft |
| MPL-2.0, EUPL-1.2 | weak-copyleft |

### 3. Package Manifest Fallback (lowest priority)

If no LICENSE file is found, the analyzer checks manifest files:

- `package.json` `"license"` field (Node.js)
- `*.gemspec` `spec.license` (Ruby)
- `Cargo.toml` `license` key (Rust)
- `pyproject.toml` `license` key (Python)

## Dependency License Scanning

### Supported Ecosystems

The analyzer detects ecosystems from manifest files and attempts to scan dependencies:

| Ecosystem | Detected By | External Tool | Fallback |
|-----------|-------------|---------------|----------|
| Go | `go.mod` | `go-licenses` | Count `go.sum` entries |
| Python | `requirements.txt`, `pyproject.toml`, `Pipfile` | `pip-licenses` | Count requirements entries |
| Ruby | `Gemfile`, `Gemfile.lock` | `license_finder` | Count lockfile entries |
| Java | `pom.xml`, `build.gradle` | Maven license plugin | Count `<dependency>` blocks |
| Node.js | `package.json` | `license-checker` | Count dependency keys |
| Rust | `Cargo.toml` | `cargo-license` | Count `Cargo.lock` packages |

### External Tools (Soft Dependencies)

When external tools are available, they provide per-dependency license identification. The analyzer tries multiple command variants for each ecosystem and falls back gracefully:

| Ecosystem | Direct command | Runner fallback |
|-----------|---------------|-----------------|
| Go | `go-licenses` | — |
| Python | `pip-licenses` | `python -m piplicenses` / `python3 -m piplicenses` |
| Ruby | `license_finder` | `gem exec license_finder` |
| Node.js | `license-checker` | — |
| Rust | `cargo-license` | `cargo license` |

For Python projects, the analyzer also checks for `pip-licenses` inside `.venv/` or `venv/` virtual environments before trying system commands.

If no tool is available, the analyzer falls back to counting dependencies from lockfiles and manifests. These dependencies are recorded with an "unknown" license type.

### Performance

The license analyzer is optimized for batch imports of many repositories:

- **Command caching**: The first repository probes which tool variant works for each ecosystem. All subsequent repositories reuse the cached result instantly — no repeated failed process spawns.
- **No download-on-demand**: Runners like `npx --yes` or `go run ...@latest` that download/compile tools are not used, as they add 10-30s per repo. Install tools globally instead.
- **Parallel execution**: License analysis and team matching run concurrently in the repository handler.
- **Fast fallback**: When no external tool is found, manifest-based dependency counting is near-instant (file reads only).

To get the best results, pre-install tools globally:

```bash
go install github.com/google/go-licenses@latest  # Go
pip install pip-licenses                           # Python
gem install license_finder                         # Ruby
npm install -g license-checker                     # Node.js
cargo install cargo-license                        # Rust
```

### Risk Classification

Dependency risk is assessed based on detected license types:

| Risk Level | Criteria |
|------------|----------|
| **low** | All dependency licenses are permissive |
| **medium** | Weak-copyleft licenses present (LGPL, MPL, EUPL) but no strong copyleft |
| **high** | Strong copyleft (GPL, AGPL) present, or majority of licenses are unknown |
| **unknown** | No dependency license data available |

## License Normalization

Dependency tools return messy license strings — copyright notices, long-form names, leading parentheses, dual licenses, and domain names. The analyzer normalizes these into canonical SPDX identifiers in five phases:

### 1. Proprietary Detection

Before any cleanup, the raw string is checked for proprietary markers. If matched, the result is `proprietary`:

| Pattern | Examples |
|---------|----------|
| Copyright notice | `Copyright (C) 2024 Acme Corp`, `(c) 1&1 IONOS Cloud GmbH` |
| Proprietary keyword | `Proprietary License`, `UNLICENSED` |
| Internal marker | `IONOS internal`, `internal` |
| Custom URL prefix | `Custom: https://example.com/license` |
| Domain-as-license | `ionos.com`, `profitbricks.com`, `example.io` |

### 2. Clean

Strip leading `("(`, trailing `,;)"*`, and surrounding whitespace. This handles messy tool output like `"MIT`, `(GPL-2.0`, `Apache*`.

### 3. Dual License Split

If the string contains `/` or ` OR `, it is split and the first recognized SPDX ID is returned:

| Input | Output |
|-------|--------|
| `MIT/Apache-2.0` | `MIT` |
| `(MIT OR CC0-1.0)` | `MIT` |

### 4. Long-form Pattern Matching

Common long-form names and aliases are mapped to canonical SPDX IDs:

| Input | Output |
|-------|--------|
| `Apache License, Version 2.0` / `Apache 2.0` / `Apache` | `Apache-2.0` |
| `The MIT License` | `MIT` |
| `New BSD` | `BSD-3-Clause` |
| `Simplified BSD` / `BSD 2-Clause` | `BSD-2-Clause` |
| `0BSD` | `0BSD` |
| `GNU General Public License v2` / `GPLv2` | `GPL-2.0` |
| `GNU LGPL 3` / `GNU Lesser General Public License` | `LGPL-3.0` / `LGPL-2.1` |
| `CDDL + GPLv2 with classpath exception` | `CDDL-1.0` |
| `UNKNOWN` | `unknown` |
| `ruby` | `Ruby` |

### 5. Fallback

If no pattern matches, the cleaned string is returned as-is.

## Generated Annotations

The license analyzer produces these annotations on TechnologyArtifact resources:

### Repository License

| Annotation | Description | Example |
|------------|-------------|---------|
| `license/spdx` | SPDX license identifier | `Apache-2.0` |
| `license/file` | Detected license file name | `LICENSE` |
| `license/category` | License category | `permissive` |

### Dependency Licenses

| Annotation | Description | Example |
|------------|-------------|---------|
| `license/dependencies/count` | Total dependency count | `142` |
| `license/dependencies/ecosystems` | Detected ecosystems (comma-separated) | `go,python` |
| `license/dependencies/licenses` | Unique license types found | `Apache-2.0,BSD-3-Clause,MIT` |
| `license/dependencies/copyleft` | Whether copyleft deps exist | `false` |
| `license/dependencies/risk` | Overall risk level | `low` |
| `license/dependencies/*/count` | Per-license-type count | `license/dependencies/MIT/count: 80` |

## Querying License Data

Use the search and query system to find repositories by license characteristics:

```
# Find all repositories with copyleft licenses
TechnologyArtifact: license/category == "copyleft"

# Find repos with high dependency risk
TechnologyArtifact: license/dependencies/risk == "high"

# Find repos with copyleft dependencies
TechnologyArtifact: license/dependencies/copyleft == "true"

# Find repos using a specific license
TechnologyArtifact: license/spdx == "MIT"

# Find repos with Go dependencies
TechnologyArtifact: license/dependencies/ecosystems *= "go"
```

## Aggregating License Profiles

Use [computed annotations](/doc/computed_annotations) to build a licensing profile across products or services. For example, on an ApplicationComponent that groups multiple repositories:

```ruby
# Count repos per license category
computed_annotation 'computed/license_permissive_count',
                    title: 'Permissive License Repos',
                    type: Integer do
  artifacts = outgoing_transitive('TechnologyArtifact: license/category == "permissive"')
  count(artifacts)
end

# Detect if any copyleft dependencies exist in the portfolio
computed_annotation 'computed/license_copyleft_present',
                    title: 'Copyleft Dependencies',
                    filter: :word do
  artifacts = outgoing_transitive('TechnologyArtifact: license/dependencies/copyleft == "true"')
  count(artifacts).positive? ? "true" : "false"
end

# Collect all unique dependency licenses across the portfolio
computed_annotation 'computed/license_types',
                    title: 'All License Types',
                    filter: :list,
                    list: true do
  collect(outgoing_transitive(:TechnologyArtifact), 'license/dependencies/licenses')
end

# Highest dependency risk across all repos
computed_annotation 'computed/license_max_risk',
                    title: 'Max License Risk',
                    filter: :word do
  risks = collect(outgoing_transitive(:TechnologyArtifact), 'license/dependencies/risk')
  %w[high medium low unknown].find { |r| risks.include?(r) }
end
```

## Example Output

After importing a Go repository with an Apache-2.0 license:

```yaml
apiVersion: architecture/v1alpha1
kind: TechnologyArtifact
metadata:
  name: "Repo:my-service"
  annotations:
    artifact/type: repo
    repository/git: git@github.com:org/my-service.git
    license/spdx: Apache-2.0
    license/file: LICENSE
    license/category: permissive
    license/dependencies/count: "87"
    license/dependencies/ecosystems: go
    license/dependencies/licenses: Apache-2.0,BSD-3-Clause,MIT
    license/dependencies/copyleft: "false"
    license/dependencies/risk: low
    license/dependencies/MIT/count: "42"
    license/dependencies/Apache-2.0/count: "30"
    license/dependencies/BSD-3-Clause/count: "15"
spec:
  suppliedBy:
    technologyComponents:
      - "Git:Github"
```

## Web UI

License information is displayed in the TechnologyArtifact detail view with:

- A color-coded badge for the repository license (green = permissive, yellow = weak-copyleft, red = copyleft)
- Dependency count and ecosystem badges
- Risk level indicator
- Expandable per-license-type breakdown with counts

## Troubleshooting

### License Not Detected

If a repository shows `NOASSERTION` for its license:

1. Verify the LICENSE file exists in the repository root
2. Check that the license text matches a known pattern (some custom licenses won't match)
3. Add an SPDX header to a source file for reliable detection

### All Dependencies Show "unknown" License

This means no external scanning tool was available. The analyzer fell back to counting dependencies from manifest/lockfiles. Install the appropriate tool for the ecosystem (see [External Tools](#external-tools) above).

### High Risk Due to Unknown Licenses

A high proportion of "unknown" licenses triggers a "high" risk classification. This is by design - unknown licenses should be investigated. Install ecosystem-specific tools to resolve unknowns into actual license identifiers.
