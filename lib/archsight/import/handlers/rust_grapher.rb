# frozen_string_literal: true

require_relative "grapher"
require_relative "../registry"

# RustGrapher — analyses a Rust repository and generates a GraphViz DOT
# graph of its crate/module structure, stored as architecture/rust/modules
# on the TechnologyArtifact.
#
# Supports single-crate projects (Cargo.toml at root) and Cargo workspaces
# (root Cargo.toml with [workspace] members). Uses pure static regex analysis
# of `use crate::` and `use <workspace_member>::` statements — no Rust
# toolchain required.
#
# File-to-package mapping follows Rust conventions:
#   src/lib.rs, src/main.rs → crate root package
#   src/foo.rs              → crate/foo
#   src/foo/mod.rs          → crate/foo  (directory module)
#   src/foo/bar.rs          → crate/foo/bar → capped to crate/foo
#
# Configuration:
#   import/config/path     - Path to the Rust repository root
#   import/config/ranksep  - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep  - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::RustGrapher < Archsight::Import::Handlers::Grapher
  def self.language_name = "rust"

  def self.applicable?(path)
    File.exist?(File.join(path, "Cargo.toml")) ||
      Dir.glob(File.join(path, "*/Cargo.toml")).any?
  end

  def wrap_single_module?
    true
  end

  SKIP_DIRS = %w[target .git tests test benches examples].freeze

  # MAX_PKG_DEPTH = 2: crate/feature is the natural Rust module depth.
  MAX_PKG_DEPTH = 2

  # use crate::foo::bar::Baz — capture everything after crate::
  USE_CRATE_RE = /^\s*use\s+crate::((?:\w+::)*\w+)/

  # use some_crate::path — capture full path for workspace dep resolution
  USE_PATH_RE = /^\s*use\s+((?:\w+::)*\w+)/

  # Identifiers that are never workspace crate names
  BUILTIN_PREFIXES = %w[crate super self].freeze

  private

  # ── Module discovery ─────────────────────────────────────────────────────

  def discover_modules(repo_root)
    return workspace_discover(repo_root) if workspace?(repo_root)

    mod_name = parse_crate_name(File.join(repo_root, "Cargo.toml")) ||
               File.basename(repo_root)
    [[".", mod_name]]
  end

  def workspace?(repo_root)
    content = File.read(File.join(repo_root, "Cargo.toml"), encoding: "utf-8")
    content.match?(/^\[workspace\]/)
  rescue StandardError
    false
  end

  def workspace_discover(repo_root)
    members = workspace_members(repo_root)

    if members.empty?
      # Workspace with no members — fall back to treating root as a single crate
      mod_name = parse_crate_name(File.join(repo_root, "Cargo.toml")) ||
                 File.basename(repo_root)
      return [[".", mod_name]]
    end

    members.filter_map do |rel_dir|
      mod_name = parse_crate_name(File.join(repo_root, rel_dir, "Cargo.toml")) ||
                 File.basename(rel_dir)
      [rel_dir, mod_name]
    end
  end

  def workspace_members(repo_root)
    content = File.read(File.join(repo_root, "Cargo.toml"), encoding: "utf-8")
    ws_section = content[/^\[workspace\].*?(?=^\[|\z)/m] || ""
    members_block = ws_section[/\bmembers\s*=\s*\[(.*?)\]/m, 1] || ""
    raw = members_block.scan(/"([^"]+)"/).flatten

    raw.flat_map { |pat| Dir.glob(File.join(repo_root, pat)) }
       .map { |d| d.delete_prefix("#{repo_root}/") }
       .reject { |rel| SKIP_DIRS.any? { |d| rel.split("/").include?(d) } }
       .select { |rel| File.exist?(File.join(repo_root, rel, "Cargo.toml")) }
  end

  def parse_crate_name(cargo_toml_path)
    content = File.read(cargo_toml_path, encoding: "utf-8")
    # Extract from [package] only — avoid matching workspace.package or other sections
    pkg_section = content[/^\[package\].*?(?=^\[|\z)/m]
    pkg_section&.match(/^name\s*=\s*"([^"]+)"/)&.[](1)
  rescue StandardError
    nil
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    # Rust normalises Cargo.toml hyphens to underscores in `use` statements
    known_crates = modules.each_with_object({}) do |(_, mod_name), h|
      h[mod_name.gsub("-", "_")] = mod_name
    end

    all_pkgs = {}

    modules.each do |rel_dir, mod_name|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      src_dir = Dir.exist?(File.join(mod_dir, "src")) ? File.join(mod_dir, "src") : mod_dir
      scan_src_dir(src_dir, mod_name, known_crates, all_pkgs)
    end

    pkg_set = all_pkgs.keys.to_set
    all_pkgs.each_value { |deps| deps.select! { |d| pkg_set.include?(d) } }

    all_pkgs
  end

  # ── Scanning ─────────────────────────────────────────────────────────────

  def scan_src_dir(src_dir, mod_name, known_crates, all_pkgs)
    Dir.glob(File.join(src_dir, "**", "*.rs")).each do |rs_file|
      rel = rs_file.delete_prefix("#{src_dir}/")
      rel_parts = rel.split("/")
      next if rel_parts.any? { |p| SKIP_DIRS.include?(p) }

      pkg = cap_depth(file_to_pkg(rs_file, src_dir, mod_name), mod_name)
      all_pkgs[pkg] ||= []

      # lib.rs and main.rs are crate entry points — they wire binaries and
      # re-export the public API but don't express module architecture.
      # Extracting their deps would produce hub-spoke edges from the invisible
      # root node to every child, which matches no other language grapher's style.
      next if %w[lib.rs main.rs].include?(rel)

      extract_deps(rs_file, mod_name, known_crates).each do |dep|
        dep = cap_depth(dep, mod_name)
        next if dep == pkg || all_pkgs[pkg].include?(dep)

        all_pkgs[pkg] << dep
      end
    end
  end

  # ── Dependency extraction ─────────────────────────────────────────────────

  def extract_deps(rs_file, mod_name, known_crates)
    content = File.read(rs_file, encoding: "utf-8")
    deps = []

    content.each_line do |line|
      # Intra-crate: use crate::foo::bar::Baz
      if (m = line.match(USE_CRATE_RE))
        path = m[1].gsub("::", "/")
        deps << "#{mod_name}/#{path}"
        next
      end

      # Cross-crate workspace: use other_crate::path::to::Type
      # Check workspace membership before any stdlib filtering so that
      # workspace crates named "core" or "alloc" are resolved correctly.
      next unless (m = line.match(USE_PATH_RE))

      parts = m[1].split("::")
      next if BUILTIN_PREFIXES.include?(parts.first)

      target_mod = known_crates[parts.first]
      next unless target_mod

      # Cap the sub-path to MAX_PKG_DEPTH-1 levels so the dep lands on a
      # real package rather than a type name (e.g. ::User → drop it).
      if parts.length > 1
        sub_parts = parts[1..].first(MAX_PKG_DEPTH - 1)
        deps << "#{target_mod}/#{sub_parts.join("/")}"
      else
        deps << target_mod
      end
    end

    deps.uniq
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    []
  end

  # ── Package path helpers ──────────────────────────────────────────────────

  # Maps a .rs file to its package path.
  #   src/lib.rs, src/main.rs → crate root (mod_name)
  #   src/foo/mod.rs          → mod_name/foo
  #   src/foo.rs              → mod_name/foo
  #   src/foo/bar.rs          → mod_name/foo/bar (capped later)
  def file_to_pkg(abs_path, src_dir, mod_name)
    rel = abs_path.delete_prefix("#{src_dir}/").delete_suffix(".rs")
    return mod_name if %w[lib main].include?(rel)

    rel = rel.delete_suffix("/mod")
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

Archsight::Import::Registry.register("rust-grapher", Archsight::Import::Handlers::RustGrapher)
