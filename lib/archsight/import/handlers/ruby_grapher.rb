# frozen_string_literal: true

require_relative "grapher"
require_relative "../registry"

# RubyGrapher handler - analyses a Ruby repository and generates a GraphViz DOT
# graph of its gem/package structure, stored as architecture/modules on
# the TechnologyArtifact so it can be rendered in the frontend.
#
# Uses static regex analysis of require/require_relative statements.
# Package paths are normalised to "/" separators internally so they are
# compatible with the generic Grapher layout engine.
#
# Configuration:
#   import/config/path     - Path to the Ruby repository root
#   import/config/ranksep  - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep  - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::RubyGrapher < Archsight::Import::Handlers::Grapher
  def self.language_name = "ruby"

  def self.applicable?(path)
    File.exist?(File.join(path, "Gemfile")) ||
      Dir.glob(File.join(path, "*.gemspec")).any? ||
      Dir.glob(File.join(path, "*/*.gemspec")).any?
  end

  def wrap_single_module?
    true
  end

  SKIP_DIRS = %w[test spec tests vendor .git node_modules tmp log coverage .bundle
                 pkg doc docs generated].freeze

  # Packages with more than this many path components are folded into their ancestor.
  # Ruby gems use lib/<gem>/<feature>.rb, so depth 2 gives one level of features.
  MAX_PKG_DEPTH = 2

  private

  # ── Module discovery ─────────────────────────────────────────────────────

  def discover_modules(repo_root)
    # Root-level gemspecs → single-gem repo.
    # Use the actual top-level directory in lib/ as the module name so that
    # package paths (which are lib-relative) match without re-prefixing.
    root_gemspecs = Dir.glob(File.join(repo_root, "*.gemspec"))
    if root_gemspecs.any?
      return root_gemspecs.map do |path|
        lib = File.join(repo_root, "lib")
        mod_name = lib_top_dir(lib) || gemspec_name(path) || File.basename(path, ".gemspec")
        [".", mod_name]
      end
    end

    # Subdirectory gemspecs → monorepo
    sub_gemspecs = Dir.glob(File.join(repo_root, "*/*.gemspec")).reject do |p|
      SKIP_DIRS.any? { |d| p.split("/").include?(d) }
    end
    if sub_gemspecs.any?
      return sub_gemspecs.sort.map do |path|
        rel_dir = File.dirname(path).delete_prefix("#{repo_root}/")
        lib = File.join(repo_root, rel_dir, "lib")
        mod_name = lib_top_dir(lib) || gemspec_name(path) || File.basename(path, ".gemspec")
        [rel_dir, mod_name]
      end
    end

    # Fallback: Gemfile without gemspec
    lib = File.join(repo_root, "lib")
    [[".", lib_top_dir(lib) || File.basename(repo_root)]]
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    # Build a map of lib dirs for cross-module require resolution:
    # mod_name => absolute lib dir
    lib_dirs = modules.filter_map do |rel_dir, mod_name|
      abs_lib = File.join(rel_dir == "." ? repo_root : File.join(repo_root, rel_dir), "lib")
      [mod_name, abs_lib] if Dir.exist?(abs_lib)
    end.to_h

    all_pkgs = {}

    modules.each do |_rel_dir, mod_name| # rubocop:disable Style/HashEachMethods
      lib_dir = lib_dirs[mod_name]
      next unless lib_dir

      scan_lib_dir(lib_dir, mod_name, lib_dirs, all_pkgs)
    end

    all_pkgs
  end

  # ── Scanning helpers ──────────────────────────────────────────────────────

  def scan_lib_dir(lib_dir, mod_name, lib_dirs, all_pkgs)
    safe_glob(File.join(lib_dir, "**", "*.rb")).each do |rb_file|
      rel_parts = rb_file.delete_prefix("#{lib_dir}/").split("/")
      next if rel_parts.any? { |p| SKIP_DIRS.include?(p) }

      pkg = file_to_pkg(rb_file, lib_dir, mod_name)
      pkg = cap_depth(pkg, mod_name)
      all_pkgs[pkg] ||= []

      extract_deps(rb_file, lib_dir, mod_name, lib_dirs).each do |dep|
        dep = cap_depth(dep, mod_name)
        next if dep == pkg || all_pkgs[pkg].include?(dep)

        all_pkgs[pkg] << dep
      end
    end
  end

  def extract_deps(rb_file, lib_dir, mod_name, lib_dirs)
    content = File.read(rb_file, encoding: "utf-8")
    deps = []

    content.scan(/^\s*require\s+["']([^"']+)["']/) do |(req)|
      dep = resolve_require(req, lib_dirs)
      deps << dep if dep
    end

    content.scan(/^\s*require_relative\s+["']([^"']+)["']/) do |(req)|
      dep = resolve_require_relative(req, rb_file, lib_dir, mod_name)
      deps << dep if dep
    end

    deps.uniq
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    []
  end

  # Resolve an absolute `require` path against all known lib dirs.
  def resolve_require(req, lib_dirs)
    lib_dirs.each do |mod_name, lib_dir|
      rb_path = File.join(lib_dir, "#{req}.rb")
      return file_to_pkg(rb_path, lib_dir, mod_name) if File.exist?(rb_path)

      # require 'mod_name' or require 'mod_name/sub' with no .rb — treat as pkg path
      return req if Dir.exist?(File.join(lib_dir, req))
    end
    nil
  end

  # Resolve a `require_relative` path relative to the current file.
  def resolve_require_relative(req, rb_file, lib_dir, mod_name)
    base_dir = File.dirname(rb_file)
    expanded = File.expand_path(req, base_dir)

    rb_path = expanded.end_with?(".rb") ? expanded : "#{expanded}.rb"
    return file_to_pkg(rb_path, lib_dir, mod_name) if File.exist?(rb_path)

    # Directory index file: foo/foo.rb
    if Dir.exist?(expanded)
      index = File.join(expanded, "#{File.basename(expanded)}.rb")
      return file_to_pkg(index, lib_dir, mod_name) if File.exist?(index)
    end

    nil
  end

  # Convert an absolute .rb path to a slash-separated package path.
  # Uses the full lib-relative path (without .rb) so that flat files like
  # lib/gem/database.rb become their own package (gem/database) rather than
  # collapsing into the root gem package. cap_depth then folds deeper paths.
  def file_to_pkg(rb_path, lib_dir, mod_name)
    rel = rb_path.delete_prefix("#{lib_dir}/").delete_suffix(".rb")
    rel == mod_name ? mod_name : rel
  end

  # Fold packages deeper than MAX_PKG_DEPTH levels into their ancestor.
  def cap_depth(pkg, mod_name)
    suffix = pkg.delete_prefix("#{mod_name}/")
    return mod_name if suffix == pkg # pkg == mod_name exactly

    parts = suffix.split("/")
    return pkg if parts.length <= MAX_PKG_DEPTH - 1

    "#{mod_name}/#{parts.first(MAX_PKG_DEPTH - 1).join("/")}"
  end

  # Returns the single top-level directory inside lib/, which is the gem name
  # as used on the filesystem (underscores, not hyphens).
  def lib_top_dir(lib_dir)
    return nil unless Dir.exist?(lib_dir)

    dirs = Dir.children(lib_dir).select { |e| File.directory?(File.join(lib_dir, e)) }
    dirs.length == 1 ? dirs.first : nil
  end

  def gemspec_name(gemspec_path)
    content = begin
      File.read(gemspec_path, encoding: "utf-8")
    rescue StandardError
      ""
    end
    match = content.match(/\.name\s*=\s*["']([^"']+)["']/)
    match&.captures&.first
  end
end

Archsight::Import::Registry.register("ruby-grapher", Archsight::Import::Handlers::RubyGrapher)
