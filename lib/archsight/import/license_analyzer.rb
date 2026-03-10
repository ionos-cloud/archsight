# frozen_string_literal: true

require "open3"
require "json"
require "spdx-licenses"
require "archsight/import"

# License detection and dependency license scanning for repositories
#
# Detects the repository's own license from LICENSE/COPYING files and SPDX headers,
# then scans dependency licenses using language-specific tools when available.
#
# @example
#   analyzer = Archsight::Import::LicenseAnalyzer.new("/path/to/repo")
#   result = analyzer.analyze
#   result["license_spdx"]     # => "Apache-2.0"
#   result["dependency_risk"]  # => "low"
class Archsight::Import::LicenseAnalyzer
  # SPDX patterns: match against LICENSE/COPYING file content
  # Order matters - more specific patterns first
  SPDX_PATTERNS = [
    { id: "Apache-2.0",   re: /Apache License.*(?:Version 2|v2\.0)/mi },
    { id: "MIT",          re: /\bMIT License\b|Permission is hereby granted, free of charge/mi },
    { id: "BSD-3-Clause", re: /BSD 3-Clause|Redistribution and use.*three conditions/mi },
    { id: "BSD-2-Clause", re: /BSD 2-Clause|Simplified BSD/mi },
    { id: "GPL-3.0",      re: /GNU GENERAL PUBLIC LICENSE.*Version 3/mi },
    { id: "GPL-2.0",      re: /GNU GENERAL PUBLIC LICENSE.*Version 2/mi },
    { id: "AGPL-3.0",     re: /GNU AFFERO GENERAL PUBLIC LICENSE.*Version 3/mi },
    { id: "LGPL-3.0",     re: /GNU LESSER GENERAL PUBLIC LICENSE.*Version 3/mi },
    { id: "LGPL-2.1",     re: /GNU LESSER GENERAL PUBLIC LICENSE.*Version 2\.1/mi },
    { id: "MPL-2.0",      re: /Mozilla Public License.*(?:Version 2|v2\.0)/mi },
    { id: "ISC",          re: /\bISC License\b|ISC\s+license/mi },
    { id: "Unlicense",    re: /\bThis is free and unencumbered software\b/mi },
    { id: "CC0-1.0",      re: /Creative Commons.*CC0|CC0 1\.0 Universal/mi },
    { id: "BSL-1.0",      re: /Boost Software License/mi },
    { id: "BUSL-1.1",     re: /Business Source License.*1\.1/mi },
    { id: "EUPL-1.2",     re: /European Union Public Licen[cs]e.*1\.2/mi }
  ].freeze

  # License category classification
  CATEGORIES = {
    "permissive" => %w[Apache-2.0 MIT BSD-3-Clause BSD-2-Clause ISC Unlicense CC0-1.0 BSL-1.0 0BSD Ruby],
    "copyleft" => %w[GPL-3.0 GPL-2.0 AGPL-3.0],
    "weak-copyleft" => %w[LGPL-3.0 LGPL-2.1 MPL-2.0 EUPL-1.2 CDDL-1.0],
    "source-available" => %w[BUSL-1.1],
    "proprietary" => %w[proprietary]
  }.freeze

  CATEGORY_LOOKUP = CATEGORIES.each_with_object({}) do |(cat, ids), h|
    ids.each { |id| h[id] = cat }
  end.freeze

  # Proprietary / copyright patterns — matched against the trimmed string
  PROPRIETARY_RE = /
    \bcopyright\b | \bproprietary\b | \bUNLICENSED\b |
    \binternal\b |
    \ACustom:\s |
    \b[a-z0-9-]+\.(com|io|de|net|org|cloud)\b |
    \(c\)\s
  /xi

  # Custom non-SPDX values we accept
  CUSTOM_LICENSE_VALUES = Set.new(%w[NOASSERTION proprietary unknown]).freeze

  # License file names to search (in order of priority)
  LICENSE_FILES = %w[
    LICENSE LICENSE.md LICENSE.txt
    LICENCE LICENCE.md LICENCE.txt
    COPYING COPYING.md COPYING.txt
  ].freeze

  # Manifest files that indicate an ecosystem
  ECOSYSTEM_MANIFESTS = {
    "go" => %w[go.mod],
    "python" => %w[requirements.txt setup.py pyproject.toml Pipfile],
    "ruby" => %w[Gemfile Gemfile.lock],
    "java" => %w[pom.xml build.gradle build.gradle.kts],
    "nodejs" => %w[package.json],
    "rust" => %w[Cargo.toml]
  }.freeze

  # Map scc language names to ecosystem keys.
  # When scc data is available, only ecosystems matching detected languages are probed.
  LANGUAGE_TO_ECOSYSTEM = {
    "Go" => "go",
    "Python" => "python",
    "Ruby" => "ruby",
    "Java" => "java", "Kotlin" => "java", "Groovy" => "java", "Scala" => "java",
    "JavaScript" => "nodejs", "TypeScript" => "nodejs", "JSX" => "nodejs", "TSX" => "nodejs",
    "Rust" => "rust"
  }.freeze

  # Cache of resolved command variants per ecosystem.
  # After the first repo probes which tool works, all subsequent repos reuse it.
  # { "go" => ["go-licenses", ...args], "nodejs" => :none, ... }
  @@command_cache = {} # rubocop:disable Style/ClassVars
  @@command_cache_mutex = Mutex.new # rubocop:disable Style/ClassVars

  # @param repo_path [String] path to the git repository
  # @param options [Hash] optional settings
  # @option options [Array<String>] :languages scc language names (e.g. ["Go", "Python"])
  #   When provided, only ecosystems matching these languages are scanned for dependencies.
  def initialize(repo_path, options = {})
    @repo_path = repo_path
    @options = options
    @languages = options[:languages]
  end

  # Reset the command cache (useful in tests)
  def self.reset_command_cache!
    @@command_cache_mutex.synchronize { @@command_cache = {} } # rubocop:disable Style/ClassVars
  end

  def analyze
    repo_license = detect_repo_license
    dep_data = scan_dependencies

    result = {}
    result["license_spdx"] = repo_license[:spdx]
    result["license_file"] = repo_license[:file] if repo_license[:file]
    result["license_category"] = repo_license[:category]

    result["dependency_count"] = dep_data[:count]
    result["dependency_ecosystems"] = dep_data[:ecosystems].join(",") if dep_data[:ecosystems].any?
    result["dependency_licenses"] = dep_data[:licenses].join(",") if dep_data[:licenses].any?
    result["dependency_copyleft"] = dep_data[:copyleft].to_s
    result["dependency_risk"] = dep_data[:risk]
    result["dependency_license_counts"] = dep_data[:license_counts] if dep_data[:license_counts].any?

    result
  end

  private

  # Detect the repository's own license
  # @return [Hash] { spdx: String, file: String|nil, category: String }
  def detect_repo_license
    # 1. Try SPDX-License-Identifier headers in source files
    spdx = detect_spdx_header
    return { spdx: spdx, file: nil, category: categorize(spdx) } if spdx

    # 2. Try LICENSE/COPYING files
    license_file, content = find_license_file
    if license_file && content
      spdx = match_license_content(content)
      return { spdx: spdx, file: license_file, category: categorize(spdx) } if spdx

      return { spdx: "NOASSERTION", file: license_file, category: "unknown" }
    end

    # 3. Fallback: check manifest files for license field
    spdx = detect_from_manifests
    return { spdx: spdx, file: nil, category: categorize(spdx) } if spdx

    { spdx: "NOASSERTION", file: nil, category: "unknown" }
  end

  # Search for SPDX-License-Identifier headers in top-level source files
  def detect_spdx_header
    # Check common top-level files that might have SPDX headers
    candidates = Dir.glob(File.join(@repo_path, "*.{go,rb,py,rs,java,js,ts,c,h,cpp}"))
    candidates.concat(Dir.glob(File.join(@repo_path, "**/*.{go,rb,py,rs}")).first(20) || [])
    candidates.uniq!

    candidates.first(30).each do |file|
      next unless File.file?(file)

      # Only read first few lines
      content = File.read(file, 512)
      match = content.match(/SPDX-License-Identifier:\s*(\S+)/)
      return normalize_spdx(match[1]) if match
    rescue StandardError
      next
    end

    nil
  end

  # Find and read a LICENSE/COPYING file
  # @return [Array(String, String)] [filename, content] or [nil, nil]
  def find_license_file
    LICENSE_FILES.each do |name|
      path = File.join(@repo_path, name)
      next unless File.file?(path)

      content = File.read(path, 8192)
      return [name, content] if content && !content.empty?
    rescue StandardError
      next
    end

    [nil, nil]
  end

  # Match license file content against known patterns
  def match_license_content(content)
    SPDX_PATTERNS.each do |pattern|
      return pattern[:id] if content.match?(pattern[:re])
    end

    nil
  end

  # Detect license from package manifests
  def detect_from_manifests
    # package.json
    spdx = detect_from_package_json
    return spdx if spdx

    # gemspec files
    spdx = detect_from_gemspec
    return spdx if spdx

    # Cargo.toml
    spdx = detect_from_cargo_toml
    return spdx if spdx

    # pyproject.toml
    detect_from_pyproject_toml
  end

  def detect_from_package_json
    pkg_json = File.join(@repo_path, "package.json")
    return nil unless File.file?(pkg_json)

    data = JSON.parse(File.read(pkg_json))
    license = data["license"]
    normalize_spdx(license) if license.is_a?(String) && !license.empty?
  rescue StandardError
    nil
  end

  def detect_from_gemspec
    Dir.glob(File.join(@repo_path, "*.gemspec")).first(1).each do |gemspec|
      content = File.read(gemspec)
      match = content.match(/\.license\s*=\s*["']([^"']+)["']/)
      return normalize_spdx(match[1]) if match
    rescue StandardError
      next
    end
    nil
  end

  def detect_from_cargo_toml
    cargo = File.join(@repo_path, "Cargo.toml")
    return nil unless File.file?(cargo)

    content = File.read(cargo)
    match = content.match(/^license\s*=\s*"([^"]+)"/)
    normalize_spdx(match[1]) if match
  rescue StandardError
    nil
  end

  def detect_from_pyproject_toml
    pyproject = File.join(@repo_path, "pyproject.toml")
    return nil unless File.file?(pyproject)

    content = File.read(pyproject)
    match = content.match(/^license\s*=\s*"([^"]+)"/m) ||
            content.match(/^license\s*=\s*\{text\s*=\s*"([^"]+)"/m)
    normalize_spdx(match[1]) if match
  rescue StandardError
    nil
  end

  # Normalize SPDX identifiers from messy dependency-tool output
  #
  # Phases:
  #  1. Clean: strip leading parens, trailing punctuation, whitespace
  #  2. Proprietary detection: copyright notices, UNLICENSED, domains, internal
  #  3. Dual license split: `/` or ` OR ` → pick first recognized SPDX ID
  #  4. Pattern matching: long-form names → canonical SPDX ID
  #  5. Fallback: return cleaned string as-is
  def normalize_spdx(raw)
    return nil unless raw

    trimmed = raw.strip
    return nil if trimmed.empty?

    # Phase 2 — proprietary / copyright detection (before stripping parens)
    return "proprietary" if trimmed.match?(PROPRIETARY_RE)

    # Phase 1 — clean: strip leading parens/quotes, trailing punctuation/stars
    cleaned = trimmed.gsub(/\A["(\s]+/, "").gsub(/[,;)"*\s]+\z/, "")
    return nil if cleaned.empty?

    # Phase 3 — dual license split ("MIT/Apache-2.0", "MIT OR Apache-2.0")
    if cleaned.include?("/") || cleaned.match?(/\bOR\b/i)
      parts = cleaned.split(%r{\s*/\s*|\s+OR\s+}i)
      parts.each do |part|
        normalized = normalize_spdx_single(part.strip)
        return normalized if known_spdx?(normalized)
      end
    end

    # Phase 4+5 — single-value normalization
    normalize_spdx_single(cleaned)
  end

  # Normalize a single (non-dual) SPDX-like string to its canonical form
  def normalize_spdx_single(cleaned)
    case cleaned
    when /^Apache-2/i, /^Apache\s+License/i, /^Apache\s+2/i, /^Apache$/i then "Apache-2.0"
    when /^MIT$/i, /^The MIT License/i then "MIT"
    when /^BSD[- ]3/i, /^New BSD/i then "BSD-3-Clause"
    when /^BSD[- ]2/i, /^Simplified BSD/i then "BSD-2-Clause"
    when /^0BSD$/i then "0BSD"
    when /^GPL-?3/i, /^GPLv3/i, /^GNU General Public License\s*v?3/i then "GPL-3.0"
    when /^GPL-?2/i, /^GPLv2/i, /^GNU General Public License\s*v?2/i then "GPL-2.0"
    when /^AGPL-3/i then "AGPL-3.0"
    when /^LGPL-3/i, /^GNU LGPL\s*3/i, /^GNU Lesser.*3/i then "LGPL-3.0"
    when /^LGPL-2/i, /^GNU LGPL\s*2/i, /^GNU Lesser.*2/i then "LGPL-2.1"
    when /^GNU Lesser/i, /^GNU LGPL$/i then "LGPL-2.1"
    when /^MPL-2/i then "MPL-2.0"
    when /^CDDL/i then "CDDL-1.0"
    when /^ISC$/i then "ISC"
    when /^Unlicense$/i then "Unlicense"
    when /^EUPL-1/i then "EUPL-1.2"
    when /^UNKNOWN$/i then "unknown"
    when /^ruby$/i then "Ruby"
    else cleaned
    end
  end

  # Check if a value is a known SPDX ID or one of our custom values
  def known_spdx?(value)
    CUSTOM_LICENSE_VALUES.include?(value) || SpdxLicenses.exist?(value)
  end

  # Categorize a license SPDX identifier
  def categorize(spdx)
    CATEGORY_LOOKUP[spdx] || "unknown"
  end

  # Scan dependencies across detected ecosystems
  # @return [Hash] { count:, ecosystems:, licenses:, copyleft:, risk:, license_counts: }
  def scan_dependencies
    ecosystems = detect_ecosystems
    return empty_dependency_result if ecosystems.empty?

    all_licenses = {}

    ecosystems.each do |ecosystem|
      licenses = scan_ecosystem(ecosystem)
      licenses.each do |name, count|
        all_licenses[name] = (all_licenses[name] || 0) + count
      end
    end

    total = all_licenses.values.sum
    unique_licenses = all_licenses.keys.sort
    copyleft = detect_copyleft(unique_licenses)
    risk = assess_risk(unique_licenses, total)

    {
      count: total,
      ecosystems: ecosystems,
      licenses: unique_licenses,
      copyleft: copyleft,
      risk: risk,
      license_counts: all_licenses
    }
  end

  def empty_dependency_result
    { count: 0, ecosystems: [], licenses: [], copyleft: "unknown", risk: "unknown", license_counts: {} }
  end

  # Detect which ecosystems are present.
  # When languages from scc are available, only ecosystems matching those languages are checked.
  def detect_ecosystems
    candidate_ecosystems = if @languages&.any?
                             @languages.filter_map { |lang| LANGUAGE_TO_ECOSYSTEM[lang] }.uniq
                           else
                             ECOSYSTEM_MANIFESTS.keys
                           end

    candidate_ecosystems.select do |ecosystem|
      manifests = ECOSYSTEM_MANIFESTS[ecosystem]
      manifests&.any? { |file| File.exist?(File.join(@repo_path, file)) }
    end
  end

  # Scan a single ecosystem for dependency licenses
  # @return [Hash] { "MIT" => 42, "Apache-2.0" => 10, ... }
  def scan_ecosystem(ecosystem)
    case ecosystem
    when "go"     then scan_go
    when "python" then scan_python
    when "ruby"   then scan_ruby
    when "java"   then scan_java
    when "nodejs" then scan_nodejs
    when "rust"   then scan_rust
    else {}
    end
  rescue StandardError
    {}
  end

  # Try multiple command variants for a given cache_key.
  # The first repo probes all variants; subsequent repos reuse the cached winner.
  # @param cache_key [String] ecosystem identifier for caching (e.g. "go", "nodejs")
  # @param commands [Array<Array<String>>] command variants to try in order
  # @return [String, nil] stdout on success, nil if all fail
  def try_commands(cache_key, *commands)
    # Fast path: reuse cached command variant
    cached = @@command_cache_mutex.synchronize { @@command_cache[cache_key] }
    if cached
      return nil if cached == :none

      return run_command(cached)
    end

    # Probe: try each variant, cache the first that succeeds
    commands.each do |cmd|
      out = run_command(cmd)
      if out
        @@command_cache_mutex.synchronize { @@command_cache[cache_key] = cmd }
        return out
      end
    end

    # No variant worked — cache the negative result
    @@command_cache_mutex.synchronize { @@command_cache[cache_key] = :none }
    nil
  end

  # Run a single command, returning stdout on success or nil on failure
  def run_command(cmd)
    out, _, status = Open3.capture3(*cmd, chdir: @repo_path)
    status.success? ? out : nil
  rescue Errno::ENOENT
    nil
  end

  # Go: use go-licenses or count go.sum entries
  def scan_go
    # Try go-licenses first
    licenses = try_go_licenses
    return licenses if licenses

    # Fallback: count go.sum entries
    go_sum = File.join(@repo_path, "go.sum")
    return {} unless File.file?(go_sum)

    # Each module appears twice in go.sum (module + go.mod)
    lines = File.readlines(go_sum).reject { |l| l.strip.empty? }
    modules = lines.map { |l| l.split.first }.uniq
    modules.empty? ? {} : { "unknown" => modules.size }
  end

  def try_go_licenses
    args = ["report", "./...", "--template", "{{range .}}{{.LicenseName}}\n{{end}}"]
    out = try_commands("go",
                       ["go-licenses", *args])
    return nil unless out

    lines = out.lines.map(&:strip).reject(&:empty?)
    return nil if lines.empty?

    count_licenses(lines)
  end

  # Python: use pip-licenses or count requirements.txt
  def scan_python
    licenses = try_pip_licenses
    return licenses if licenses

    # Fallback: count requirements.txt entries
    req_file = File.join(@repo_path, "requirements.txt")
    return {} unless File.file?(req_file)

    lines = File.readlines(req_file).reject { |l| l.strip.empty? || l.strip.start_with?("#", "-") }
    lines.empty? ? {} : { "unknown" => lines.size }
  end

  def try_pip_licenses
    # Try repo-local venv first (not cached — path is per-repo)
    venv_pip_licenses = [
      File.join(@repo_path, ".venv/bin/pip-licenses"),
      File.join(@repo_path, "venv/bin/pip-licenses")
    ].find { |p| File.executable?(p) }

    out = run_command([venv_pip_licenses, "--format=json"]) if venv_pip_licenses

    # Then try system-level commands (cached across repos)
    out ||= try_commands("python",
                         ["pip-licenses", "--format=json"],
                         ["python", "-m", "piplicenses", "--format=json"],
                         ["python3", "-m", "piplicenses", "--format=json"])
    return nil unless out

    data = JSON.parse(out)
    return nil if data.empty?

    names = data.map { |d| d["License"] || "unknown" }
    count_licenses(names)
  rescue JSON::ParserError
    nil
  end

  # Ruby: use license_finder or count Gemfile.lock
  def scan_ruby
    licenses = try_license_finder
    return licenses if licenses

    # Fallback: count Gemfile.lock entries
    lockfile = File.join(@repo_path, "Gemfile.lock")
    return {} unless File.file?(lockfile)

    content = File.read(lockfile)
    gems = content.scan(/^\s{4}(\S+)\s/).flatten.uniq
    gems.empty? ? {} : { "unknown" => gems.size }
  end

  def try_license_finder
    out = try_commands("ruby",
                       ["license_finder", "report", "--format=csv"],
                       ["gem", "exec", "license_finder", "report", "--format=csv"])
    return nil unless out

    # CSV format: name, version, license
    names = out.lines.drop(1).filter_map do |line|
      parts = line.strip.split(",")
      parts[2]&.strip if parts.length >= 3
    end
    return nil if names.empty?

    count_licenses(names)
  end

  # Java: parse pom.xml license blocks
  def scan_java
    pom = File.join(@repo_path, "pom.xml")
    return {} unless File.file?(pom)

    content = File.read(pom)
    # Extract <dependencies> count
    deps = content.scan("<dependency>").size
    # Extract license names from <licenses> block
    license_names = content.scan(%r{<license>\s*<name>([^<]+)</name>}m).flatten
    return { "unknown" => [deps, 1].max } if license_names.empty?

    count_licenses(license_names)
  rescue StandardError
    {}
  end

  # Node.js: use license-checker or parse package.json in node_modules
  def scan_nodejs
    licenses = try_license_checker
    return licenses if licenses

    # Fallback: count package.json dependencies
    pkg = File.join(@repo_path, "package.json")
    return {} unless File.file?(pkg)

    data = JSON.parse(File.read(pkg))
    deps = (data["dependencies"]&.keys || []) + (data["devDependencies"]&.keys || [])
    deps.empty? ? {} : { "unknown" => deps.uniq.size }
  rescue StandardError
    {}
  end

  def try_license_checker
    # Only try locally-installed commands. npx --yes would download the package
    # on every repo which is too slow for batch imports.
    out = try_commands("nodejs",
                       ["license-checker", "--json"])
    return nil unless out

    data = JSON.parse(out)
    return nil if data.empty?

    names = data.values.filter_map { |info| info["licenses"] }
    return nil if names.empty?

    count_licenses(names.flatten)
  rescue JSON::ParserError
    nil
  end

  # Rust: use cargo-license or count Cargo.lock
  def scan_rust
    licenses = try_cargo_license
    return licenses if licenses

    # Fallback: count Cargo.lock entries
    lockfile = File.join(@repo_path, "Cargo.lock")
    return {} unless File.file?(lockfile)

    packages = File.read(lockfile).scan(/^\[\[package\]\]/).size
    packages.zero? ? {} : { "unknown" => packages }
  end

  def try_cargo_license
    out = try_commands("rust",
                       ["cargo-license", "--json"],
                       ["cargo", "license", "--json"])
    return nil unless out

    data = JSON.parse(out)
    return nil if data.empty?

    names = data.filter_map { |d| d["license"] }
    return nil if names.empty?

    count_licenses(names)
  rescue JSON::ParserError
    nil
  end

  # Count occurrences of each license name
  # @param names [Array<String>] license names
  # @return [Hash] { "MIT" => 42, ... }
  def count_licenses(names)
    names.each_with_object(Hash.new(0)) do |name, h|
      normalized = normalize_spdx(name) || "unknown"
      h[normalized] += 1
    end
  end

  # Check if any copyleft licenses are present in the list
  def detect_copyleft(license_names)
    copyleft_ids = CATEGORIES["copyleft"] + CATEGORIES["weak-copyleft"]
    if license_names.any? { |l| copyleft_ids.include?(l) }
      "true"
    elsif license_names.all? { |l| l == "unknown" }
      "unknown"
    else
      "false"
    end
  end

  # Assess overall license risk
  def assess_risk(license_names, total)
    return "unknown" if total.zero?

    strong_copyleft = CATEGORIES["copyleft"]
    weak_copyleft = CATEGORIES["weak-copyleft"]
    source_available = CATEGORIES["source-available"]

    has_strong = license_names.any? { |l| strong_copyleft.include?(l) }
    has_weak = license_names.any? { |l| weak_copyleft.include?(l) }
    has_source_available = license_names.any? { |l| source_available.include?(l) }
    unknown_count = license_names.count { |l| l == "unknown" }
    many_unknown = unknown_count.positive? && (unknown_count.to_f / license_names.size) > 0.5

    if has_strong || many_unknown || has_source_available
      "copyleft"
    elsif has_weak
      "weak-copyleft"
    else
      "low"
    end
  end
end
