# frozen_string_literal: true

require_relative "grapher"
require_relative "../registry"

# ElixirGrapher — analyses an Elixir repository and generates a GraphViz DOT
# graph of its application/package structure, stored as
# architecture/elixir/modules on the TechnologyArtifact.
#
# Supports single-app projects (mix.exs at root) and umbrella projects
# (apps/*/mix.exs). Uses pure static regex analysis of alias/import/use
# statements — no Elixir toolchain required.
#
# Configuration:
#   import/config/path     - Path to the Elixir repository root
#   import/config/ranksep  - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep  - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::ElixirGrapher < Archsight::Import::Handlers::Grapher
  def self.language_name = "elixir"

  def self.applicable?(path)
    File.exist?(File.join(path, "mix.exs")) ||
      Dir.glob(File.join(path, "apps/*/mix.exs")).any?
  end

  def wrap_single_module?
    true
  end

  SKIP_DIRS = %w[_build deps test tests .git cover priv node_modules _checkouts config].freeze

  # MAX_PKG_DEPTH = 3 allows my_app/web/controllers depth, which is common in Phoenix apps.
  MAX_PKG_DEPTH = 3

  ALIAS_RE  = /^\s*alias\s+(\w+(?:\.\w+)*(?:\.\{[^}]*\})?)/
  IMPORT_RE = /^\s*import\s+([\w.]+)/
  USE_RE    = /^\s*use\s+([\w.]+)/

  private

  # ── Module discovery ─────────────────────────────────────────────────────

  def discover_modules(repo_root)
    return umbrella_modules(repo_root) if umbrella?(repo_root)

    lib = File.join(repo_root, "lib")
    dirs = lib_all_top_dirs(lib)

    if dirs.empty?
      # No lib sub-dirs: single flat app
      app_name = parse_app_name(File.join(repo_root, "mix.exs")) || File.basename(repo_root)
      return [[".", app_name]]
    end

    # One namespace dir (common case): use it as the single module.
    # Multiple dirs (e.g. Phoenix: ic_daily + ic_daily_web + mix): each becomes its own cluster.
    # rel_dir "lib/<ns>" lets collect_packages scope scans and pkg_module_dir assign correctly.
    dirs.map { |d| ["lib/#{d}", d] }
  end

  def umbrella?(repo_root)
    content = begin
      File.read(File.join(repo_root, "mix.exs"), encoding: "utf-8")
    rescue StandardError
      ""
    end
    content.match?(/\bapps_path\s*:/) || Dir.glob(File.join(repo_root, "apps/*/mix.exs")).any?
  end

  def umbrella_modules(repo_root)
    Dir.glob(File.join(repo_root, "apps/*/mix.exs")).filter_map do |mixexs|
      app_dir = File.dirname(mixexs)
      rel_dir = app_dir.delete_prefix("#{repo_root}/")
      mod_name = parse_app_name(mixexs) || File.basename(app_dir)
      [rel_dir, mod_name]
    end
  end

  def parse_app_name(mixexs_path)
    content = File.read(mixexs_path, encoding: "utf-8")
    content.match(/\bapp:\s*:(\w+)/)[1]
  rescue StandardError
    nil
  end

  def lib_all_top_dirs(lib_dir)
    return [] unless Dir.exist?(lib_dir)

    Dir.children(lib_dir).select { |e| File.directory?(File.join(lib_dir, e)) }.sort
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    known_prefixes = modules.map { |_, mod_name| mod_name }
    all_pkgs = {}

    modules.each do |rel_dir, mod_name|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      lib_dir = Dir.exist?(File.join(mod_dir, "lib")) ? File.join(mod_dir, "lib") : mod_dir

      scan_lib_dir(lib_dir, mod_name, known_prefixes, all_pkgs)
    end

    # Drop deps that don't correspond to any scanned package: this removes references to
    # framework modules whose namespace collides with an application namespace (e.g.
    # Mix.Task from the stdlib when the app also has a lib/mix/ directory).
    pkg_set = all_pkgs.keys.to_set
    all_pkgs.each_value { |deps| deps.select! { |d| pkg_set.include?(d) } }

    all_pkgs
  end

  def scan_lib_dir(lib_dir, mod_name, known_prefixes, all_pkgs)
    safe_glob(File.join(lib_dir, "**", "*.ex")).each do |ex_file|
      rel_parts = ex_file.delete_prefix("#{lib_dir}/").split("/")
      next if rel_parts.any? { |p| SKIP_DIRS.include?(p) }

      pkg = cap_depth(file_to_pkg(ex_file, lib_dir, mod_name), mod_name)
      all_pkgs[pkg] ||= []

      extract_deps(ex_file, known_prefixes).each do |dep|
        dep = cap_depth(dep, mod_name)
        next if dep == pkg || all_pkgs[pkg].include?(dep)

        all_pkgs[pkg] << dep
      end
    end
  end

  # ── Import extraction ─────────────────────────────────────────────────────

  def extract_deps(ex_file, known_prefixes)
    content = File.read(ex_file, encoding: "utf-8")
    raw_modules = []

    content.each_line do |line|
      line.scan(ALIAS_RE)  { |(m)| raw_modules.concat(expand_alias(m)) }
      line.scan(IMPORT_RE) { |(m)| raw_modules << m }
      line.scan(USE_RE)    { |(m)| raw_modules << m }
    end

    raw_modules.filter_map { |m| resolve_dep(m, known_prefixes) }.uniq
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    []
  end

  # Expand multi-alias: MyApp.Web.{Router, Controller} → [MyApp.Web.Router, MyApp.Web.Controller]
  def expand_alias(raw)
    m = raw.match(/\A([\w.]+)\.\{([^}]+)\}/)
    unless m
      # Strip ", as: Alias" suffix if present
      return [raw.split(",").first.strip]
    end

    prefix = m[1]
    m[2].split(",").map { |n| "#{prefix}.#{n.strip}" }
  end

  def resolve_dep(mod_str, known_prefixes)
    path = module_to_path(mod_str)
    return nil unless known_prefixes.any? { |pfx| path == pfx || path.start_with?("#{pfx}/") }

    path
  end

  # CamelCase Elixir module name → snake_case/slash path
  # MyApp.Web.Controller → my_app/web/controller
  def module_to_path(mod_name)
    mod_name.split(".").map do |part|
      part.gsub(/(?<=[a-z0-9])([A-Z])/, '_\1').downcase
    end.join("/")
  end

  # ── Package path helpers ──────────────────────────────────────────────────

  # Maps a file to a package path. Prepends mod_name when lib_dir is the namespace dir
  # itself (rel_dir = "lib/<ns>") so that accounts.ex → my_app/accounts, not just accounts.
  # When lib_dir is the parent lib/ directory (rel_dir = "."), the rel path already carries
  # the namespace prefix and is returned as-is.
  def file_to_pkg(abs_path, lib_dir, mod_name)
    rel = abs_path.delete_prefix("#{lib_dir}/").delete_suffix(File.extname(abs_path))
    return mod_name if rel == mod_name
    return rel if rel.start_with?("#{mod_name}/")

    "#{mod_name}/#{rel}"
  end

  def cap_depth(pkg, mod_name)
    return pkg if pkg != mod_name && !pkg.start_with?("#{mod_name}/")

    suffix = pkg.delete_prefix("#{mod_name}/")
    return mod_name if suffix == pkg

    parts = suffix.split("/")
    return pkg if parts.length <= MAX_PKG_DEPTH - 1

    "#{mod_name}/#{parts.first(MAX_PKG_DEPTH - 1).join("/")}"
  end
end

Archsight::Import::Registry.register("elixir-grapher", Archsight::Import::Handlers::ElixirGrapher)
