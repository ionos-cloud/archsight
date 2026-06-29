# frozen_string_literal: true

require_relative "grapher"
require_relative "../registry"

# CrystalGrapher — analyses a Crystal repository and generates a GraphViz DOT
# graph of its shard/module structure, stored as architecture/crystal/modules
# on the TechnologyArtifact.
#
# Supports single-shard projects (shard.yml at root) and multi-shard monorepos
# (*/shard.yml). Uses pure static regex analysis of relative require statements
# — no Crystal toolchain required.
#
# Only relative requires (./foo or ../bar) point to internal code; absolute
# requires (require "shard_name") address installed shards in lib/ and are ignored.
#
# Configuration:
#   import/config/path     - Path to the Crystal repository root
#   import/config/ranksep  - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep  - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::CrystalGrapher < Archsight::Import::Handlers::Grapher
  def self.language_name = "crystal"

  def self.applicable?(path)
    File.exist?(File.join(path, "shard.yml")) ||
      Dir.glob(File.join(path, "*/shard.yml")).any?
  end

  def wrap_single_module?
    true
  end

  SKIP_DIRS = %w[lib spec .git bin .crystal tmp coverage].freeze

  # MAX_PKG_DEPTH = 2: my_shard/feature is the natural depth for Crystal shards.
  MAX_PKG_DEPTH = 2

  # Only relative requires point to internal code; absolute requires are external shards.
  REQUIRE_RE = %r{^\s*require\s+"(\.\.?/[^"]+)"}

  private

  # ── Module discovery ─────────────────────────────────────────────────────

  def discover_modules(repo_root)
    root_yml = File.join(repo_root, "shard.yml")

    if File.exist?(root_yml) && parse_shard_name(root_yml)
      mod_name = parse_shard_name(root_yml) ||
                 src_top_dir(File.join(repo_root, "src")) ||
                 File.basename(repo_root)
      return [[".", mod_name]]
    end

    sub_shards = Dir.glob(File.join(repo_root, "*/shard.yml")).filter_map do |yml|
      sub_dir = File.dirname(yml)
      rel_dir = sub_dir.delete_prefix("#{repo_root}/")
      next if SKIP_DIRS.any? { |d| rel_dir.split("/").include?(d) }

      mod_name = parse_shard_name(yml) || File.basename(sub_dir)
      [rel_dir, mod_name]
    end

    return sub_shards if sub_shards.any?

    # Fallback: shard.yml exists but has no name
    mod_name = src_top_dir(File.join(repo_root, "src")) || File.basename(repo_root)
    [[".", mod_name]]
  end

  def parse_shard_name(shard_yml_path)
    content = File.read(shard_yml_path, encoding: "utf-8")
    content.match(/^name:\s*(\S+)/)[1]
  rescue StandardError
    nil
  end

  def src_top_dir(src_dir)
    return nil unless Dir.exist?(src_dir)

    dirs = Dir.children(src_dir).select { |e| File.directory?(File.join(src_dir, e)) }
    dirs.length == 1 ? dirs.first : nil
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    src_dirs = modules.each_with_object({}) do |(rel_dir, mod_name), h|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      src_dir = Dir.exist?(File.join(mod_dir, "src")) ? File.join(mod_dir, "src") : mod_dir
      h[src_dir] = mod_name
    end

    all_pkgs = {}

    src_dirs.each do |src_dir, mod_name|
      scan_src_dir(src_dir, mod_name, src_dirs, all_pkgs)
    end

    # Drop deps that don't correspond to any scanned package (removes references to
    # Crystal stdlib modules whose prefix happens to match an internal namespace).
    pkg_set = all_pkgs.keys.to_set
    all_pkgs.each_value { |deps| deps.select! { |d| pkg_set.include?(d) } }

    all_pkgs
  end

  # ── Scanning ─────────────────────────────────────────────────────────────

  def scan_src_dir(src_dir, mod_name, src_dirs, all_pkgs)
    Dir.glob(File.join(src_dir, "**", "*.cr")).each do |cr_file|
      rel_parts = cr_file.delete_prefix("#{src_dir}/").split("/")
      next if rel_parts.any? { |p| SKIP_DIRS.include?(p) }

      pkg = cap_depth(file_to_pkg(cr_file, src_dir, mod_name), mod_name)
      all_pkgs[pkg] ||= []

      extract_deps(cr_file, src_dirs).each do |dep|
        dep = cap_depth(dep, mod_name)
        next if dep == pkg || all_pkgs[pkg].include?(dep)

        all_pkgs[pkg] << dep
      end
    end
  end

  # ── Require extraction ────────────────────────────────────────────────────

  def extract_deps(cr_file, src_dirs)
    content = File.read(cr_file, encoding: "utf-8")
    base_dir = File.dirname(cr_file)
    deps = []

    content.scan(REQUIRE_RE) do |(req)|
      clean = req.delete_suffix(".cr")
      expanded = File.expand_path(clean, base_dir)
      dep = resolve_cr_path(expanded, src_dirs)
      deps << dep if dep
    end

    deps.uniq
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    []
  end

  # Crystal convention: require "./foo" resolves as foo.cr OR foo/foo.cr (directory require).
  def resolve_cr_path(expanded, src_dirs)
    candidates = ["#{expanded}.cr", "#{expanded}/#{File.basename(expanded)}.cr"]
    candidates.each do |candidate|
      src_dirs.each do |src_dir, mod_name|
        next unless candidate.start_with?("#{src_dir}/")

        return file_to_pkg(candidate, src_dir, mod_name)
      end
    end
    nil
  end

  # ── Package path helpers ──────────────────────────────────────────────────

  # Uses full src-relative path (minus .cr extension). Prepends mod_name when the
  # path doesn't already carry it — handles both layouts:
  #   src/my_shard/feature.cr  (src_dir = src/)       → my_shard/feature
  #   src/feature.cr           (src_dir = src/my_shard/) → my_shard/feature
  def file_to_pkg(abs_path, src_dir, mod_name)
    rel = abs_path.delete_prefix("#{src_dir}/").delete_suffix(".cr")
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

Archsight::Import::Registry.register("crystal-grapher", Archsight::Import::Handlers::CrystalGrapher)
