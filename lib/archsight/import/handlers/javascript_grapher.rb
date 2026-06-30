# frozen_string_literal: true

require "json"
require "yaml"
require_relative "grapher"
require_relative "../registry"

# JavaScriptGrapher — analyses a JavaScript or TypeScript repository and generates
# a GraphViz DOT graph of its package/module structure, stored as
# architecture/javascript/modules on the TechnologyArtifact.
#
# Covers .js, .mjs, .cjs, .ts, .tsx, .jsx (single grapher for both JS and TS).
#
# Supported project layouts:
#   - Single package (package.json at root)
#   - NPM / Yarn workspaces ("workspaces" key in root package.json)
#   - PNPM workspaces (pnpm-workspace.yaml)
#   - Lerna (lerna.json)
#   - Nx / Turborepo (nx.json / turbo.json — scan direct subdirs)
#
# Import resolution:
#   - Relative imports (./foo, ../bar)
#   - TypeScript tsconfig.json path aliases (@/utils → src/utils)
#   - Cross-workspace package imports (@company/shared → module root)
#   - "import type" lines are ignored (no runtime dependency)
#
# Configuration:
#   import/config/path     - Path to the repository root
#   import/config/ranksep  - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep  - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::JavaScriptGrapher < Archsight::Import::Handlers::Grapher
  def self.language_name = "javascript"

  def self.applicable?(path)
    File.exist?(File.join(path, "package.json")) ||
      Dir.glob(File.join(path, "*/package.json")).any?
  end

  def wrap_single_module?
    true
  end

  SKIP_DIRS = %w[node_modules dist build .next .nuxt out .turbo .nx .cache
                 coverage .git test tests __tests__ __mocks__ e2e cypress
                 playwright .storybook storybook-static fixtures temp tmp].freeze

  SOURCE_EXTS = %w[.ts .tsx .js .jsx .mjs .cjs].freeze

  # Packages with more than this many path components are folded into their ancestor.
  # Two levels gives mod_name/feature — matching Java and Ruby conventions.
  MAX_PKG_DEPTH = 2

  FROM_RE    = /\bfrom\s+["']([^"'\n]+)["']/
  REQUIRE_RE = /\brequire\s*\(\s*["']([^"'\n]+)["']\s*\)/
  DYNAMIC_RE = /\bimport\s*\(\s*["']([^"'\n]+)["']\s*\)/
  TYPE_RE    = /\bimport\s+type\b/

  private

  # ── Module discovery ─────────────────────────────────────────────────────

  def discover_modules(repo_root)
    # PNPM workspaces
    pnpm_ws = File.join(repo_root, "pnpm-workspace.yaml")
    if File.exist?(pnpm_ws)
      modules = workspace_modules_from_globs(repo_root, pnpm_workspace_patterns(pnpm_ws))
      return modules if modules.any?
    end

    root_pkg = read_package_json(repo_root)

    # NPM / Yarn workspaces ("workspaces" key in package.json)
    ws_globs = workspace_globs_from_package(root_pkg)
    if ws_globs.any?
      modules = workspace_modules_from_globs(repo_root, ws_globs)
      return modules if modules.any?
    end

    # Lerna
    lerna_path = File.join(repo_root, "lerna.json")
    if File.exist?(lerna_path)
      lerna = safe_json(lerna_path)
      if lerna
        lerna_globs = Array(lerna["packages"])
        lerna_globs = ["packages/*"] if lerna_globs.empty?
        modules = workspace_modules_from_globs(repo_root, lerna_globs)
        return modules if modules.any?
      end
    end

    # Nx / Turborepo — scan direct subdirs
    if File.exist?(File.join(repo_root, "nx.json")) || File.exist?(File.join(repo_root, "turbo.json"))
      modules = scan_subdir_modules(repo_root)
      return modules if modules.any?
    end

    # Single module fallback
    name = root_pkg&.dig("name") || File.basename(repo_root)
    [[".", name]]
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    workspace_names = build_workspace_name_map(modules)
    all_pkgs = {}

    modules.each do |rel_dir, mod_name|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      src_root = locate_src_root(mod_dir)
      tsconfig_paths = load_tsconfig_paths(mod_dir)

      scan_source_files(src_root, mod_name, tsconfig_paths, workspace_names, all_pkgs)
    end

    all_pkgs
  end

  # ── File scanning ─────────────────────────────────────────────────────────

  def scan_source_files(src_root, mod_name, tsconfig_paths, workspace_names, all_pkgs)
    glob = File.join(src_root, "**", "*{#{SOURCE_EXTS.join(",")}}")
    Dir.glob(glob).each do |source_file|
      rel_parts = source_file.delete_prefix("#{src_root}/").split("/")
      next if rel_parts.any? { |p| SKIP_DIRS.include?(p) }

      pkg = cap_depth(file_to_pkg(source_file, src_root, mod_name), mod_name)
      all_pkgs[pkg] ||= []

      extract_imports(source_file).each do |req|
        dep = resolve_import(req, source_file, src_root, mod_name, tsconfig_paths, workspace_names)
        next unless dep

        dep = cap_depth(dep, mod_name)
        next if dep == pkg || all_pkgs[pkg].include?(dep)

        all_pkgs[pkg] << dep
      end
    end
  end

  # ── Import extraction ─────────────────────────────────────────────────────

  def extract_imports(source_file)
    content = File.read(source_file, encoding: "utf-8")
    deps = []

    content.each_line do |line|
      next if line.match?(TYPE_RE)

      line.scan(FROM_RE) { |(m)| deps << m }
    end

    content.scan(REQUIRE_RE) { |(m)| deps << m }
    content.scan(DYNAMIC_RE) { |(m)| deps << m }

    deps.uniq
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    []
  end

  # ── Import resolution ─────────────────────────────────────────────────────

  def resolve_import(req, source_file, src_root, mod_name, tsconfig_paths, workspace_names)
    return resolve_relative(req, source_file, src_root, mod_name) if req.start_with?("./", "../")

    dep = resolve_alias(req, tsconfig_paths, src_root, mod_name)
    return dep if dep

    resolve_workspace_import(req, workspace_names)
  end

  def resolve_relative(req, source_file, src_root, mod_name)
    clean = req.sub(/\.(js|ts|jsx|tsx|mjs|cjs)$/, "")
    expanded = File.expand_path(clean, File.dirname(source_file))
    return nil unless expanded.start_with?(src_root)

    if Dir.exist?(expanded)
      rel = expanded.delete_prefix("#{src_root}/")
      rel == "." ? mod_name : "#{mod_name}/#{rel}"
    else
      file_to_pkg("#{expanded}.ts", src_root, mod_name)
    end
  end

  def resolve_alias(req, tsconfig_paths, src_root, mod_name)
    tsconfig_paths.each do |prefix, target_dir|
      next unless req.start_with?(prefix)

      rest = req.delete_prefix(prefix)
      expanded = rest.empty? ? target_dir : File.join(target_dir, rest)
      next unless expanded.start_with?(src_root)

      return file_to_pkg("#{expanded}.ts", src_root, mod_name)
    end
    nil
  end

  def resolve_workspace_import(req, workspace_names)
    workspace_names.each do |pkg_name, mod_name|
      return mod_name if req == pkg_name
      next unless req.start_with?("#{pkg_name}/")

      sub = req.delete_prefix("#{pkg_name}/")
      return "#{mod_name}/#{sub.split("/").first}"
    end
    nil
  end

  # ── Package path helpers ──────────────────────────────────────────────────

  # Maps a source file to a package path: mod_name/dir where dir is the
  # file's directory within src_root. Files at the src_root level map to mod_name.
  def file_to_pkg(abs_path, src_root, mod_name)
    rel = abs_path.delete_prefix("#{src_root}/")
    dir = File.dirname(rel)
    dir == "." ? mod_name : "#{mod_name}/#{dir}"
  end

  def cap_depth(pkg, mod_name)
    # Cross-module packages (e.g. workspace deps) are returned unchanged.
    return pkg if pkg != mod_name && !pkg.start_with?("#{mod_name}/")

    suffix = pkg.delete_prefix("#{mod_name}/")
    return mod_name if suffix == pkg # pkg IS the module root

    parts = suffix.split("/")
    return pkg if parts.length <= MAX_PKG_DEPTH - 1

    "#{mod_name}/#{parts.first(MAX_PKG_DEPTH - 1).join("/")}"
  end

  # ── Source root detection ─────────────────────────────────────────────────

  def locate_src_root(mod_dir)
    %w[src lib app].each do |subdir|
      candidate = File.join(mod_dir, subdir)
      return candidate if Dir.exist?(candidate)
    end
    mod_dir
  end

  # ── tsconfig path loading ─────────────────────────────────────────────────

  def load_tsconfig_paths(mod_dir)
    paths = {}
    %w[tsconfig.json tsconfig.base.json].each do |fname|
      tsconfig_file = File.join(mod_dir, fname)
      next unless File.exist?(tsconfig_file)

      data = safe_json(tsconfig_file)
      break unless data

      raw_paths = data.dig("compilerOptions", "paths") || {}
      base_url  = data.dig("compilerOptions", "baseUrl") || "."
      base_dir  = File.expand_path(File.join(mod_dir, base_url))

      raw_paths.each do |pattern, targets|
        next if targets.empty?

        # Extract the literal prefix before the wildcard: "@/*" → "@/", "shared" → "shared"
        prefix     = pattern.sub(/\*.*$/, "")
        target_dir = File.expand_path(File.join(base_dir, targets.first.sub(/\*.*$/, "")))
        paths[prefix] = target_dir
      end
      break
    end
    paths
  end

  # ── Workspace helpers ─────────────────────────────────────────────────────

  def workspace_globs_from_package(pkg)
    return [] unless pkg

    ws = pkg["workspaces"]
    Array(ws.is_a?(Hash) ? ws["packages"] : ws)
  end

  def pnpm_workspace_patterns(pnpm_ws_path)
    data = begin
      YAML.safe_load(File.read(pnpm_ws_path, encoding: "utf-8"))
    rescue StandardError
      {}
    end
    Array(data&.dig("packages")).reject { |p| p.to_s.start_with?("!") }
  end

  def workspace_modules_from_globs(repo_root, globs)
    globs.flat_map do |glob|
      Dir.glob(File.join(repo_root, glob)).filter_map do |dir|
        next unless File.directory?(dir) && File.exist?(File.join(dir, "package.json"))

        rel = dir.delete_prefix("#{repo_root}/")
        next if rel.split("/").any? { |part| SKIP_DIRS.include?(part) }

        pkg      = read_package_json(dir)
        mod_name = pkg&.dig("name") || File.basename(dir)
        [rel, mod_name]
      end
    end.uniq
  end

  def scan_subdir_modules(repo_root)
    modules = Dir.each_child(repo_root).filter_map do |entry|
      dir = File.join(repo_root, entry)
      next unless File.directory?(dir) && !SKIP_DIRS.include?(entry) && !entry.start_with?(".")
      next unless File.exist?(File.join(dir, "package.json"))

      pkg      = read_package_json(dir)
      mod_name = pkg&.dig("name") || entry
      [entry, mod_name]
    end
    modules.sort_by { |rel, _| rel }
  end

  def build_workspace_name_map(modules)
    modules.each_with_object({}) do |(_rel_dir, mod_name), map|
      map[mod_name] = mod_name
    end
  end

  def read_package_json(dir)
    safe_json(File.join(dir, "package.json"))
  end

  def safe_json(path)
    JSON.parse(File.read(path, encoding: "utf-8"))
  rescue JSON::ParserError, Errno::ENOENT, Encoding::InvalidByteSequenceError
    nil
  end
end

Archsight::Import::Registry.register("javascript-grapher", Archsight::Import::Handlers::JavaScriptGrapher)
