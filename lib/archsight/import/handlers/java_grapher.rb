# frozen_string_literal: true

require "find"
require_relative "grapher"
require_relative "../registry"

# JavaGrapher handler - analyses a Java repository and generates a GraphViz DOT
# graph of its package/module structure, stored as architecture/modules on the
# TechnologyArtifact so it can be rendered in the frontend.
#
# Understands Maven (pom.xml) single and multi-module projects as well as
# Gradle (build.gradle / settings.gradle) layouts. Scanning is pure Ruby —
# no JDK or build tool installation required.
#
# Configuration:
#   import/config/path     - Path to the Java repository root
#   import/config/ranksep  - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep  - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::JavaGrapher < Archsight::Import::Handlers::Grapher
  def self.language_name = "java"

  def self.applicable?(path)
    File.exist?(File.join(path, "pom.xml")) ||
      File.exist?(File.join(path, "build.gradle")) ||
      File.exist?(File.join(path, "build.gradle.kts")) ||
      Dir.glob(File.join(path, "*/pom.xml")).any?
  end

  SKIP_DIRS = %w[test tests generated target build .git node_modules .gradle resources].freeze

  # Cap relative package depth at 2 levels to keep the graph readable.
  # Packages deeper than this are folded into their depth-2 ancestor.
  MAX_PKG_DEPTH = 2

  private

  def wrap_single_module?
    true
  end

  # Always render package nodes: Java packages with direct files should remain
  # visible even when their label matches the enclosing cluster label.
  def show_root_package_node?
    true
  end

  # Only suppress edges to structural ancestors (paths not in pkg_set).
  # Java packages with both direct files and sub-packages must keep their edges.
  def suppress_edge_to?(dep, pkg_set, has_children)
    has_children.include?(dep) && !pkg_set.include?(dep)
  end

  # ── Module discovery ─────────────────────────────────────────────────────

  def discover_modules(repo_root)
    discover_maven_modules(repo_root) ||
      discover_gradle_modules(repo_root) ||
      discover_source_fallback(repo_root) ||
      []
  end

  def discover_maven_modules(repo_root)
    root_pom = File.join(repo_root, "pom.xml")
    return unless File.exist?(root_pom)

    sub_dirs = maven_submodule_dirs(root_pom)
    if sub_dirs.any?
      modules = sub_module_list(repo_root, sub_dirs)
      return modules if modules.any?
    end

    single_module_from_root(repo_root)
  end

  def discover_gradle_modules(repo_root)
    settings = ["settings.gradle", "settings.gradle.kts"]
               .map { |f| File.join(repo_root, f) }
               .find { |f| File.exist?(f) }
    return unless settings

    includes = gradle_includes(settings)
    if includes.any?
      modules = sub_module_list(repo_root, includes)
      return modules if modules.any?
    end

    single_module_from_root(repo_root)
  end

  def discover_source_fallback(repo_root)
    single_module_from_root(repo_root)
  end

  def sub_module_list(repo_root, rel_dirs)
    rel_dirs.filter_map do |rel|
      abs = File.join(repo_root, rel)
      next unless File.directory?(abs)

      src = find_source_dir(abs)
      next unless src

      pkg_prefix = common_java_prefix(src)
      next unless pkg_prefix

      [rel, pkg_prefix]
    end
  end

  def single_module_from_root(repo_root)
    src = find_source_dir(repo_root)
    return unless src

    pkg_prefix = common_java_prefix(src)
    return unless pkg_prefix

    [[".", pkg_prefix]]
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    all_pkgs = {}
    modules.each do |rel_dir, mod_name|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      src = find_source_dir(mod_dir)
      next unless src

      scan_java_packages(src, mod_name).each do |pkg, deps|
        all_pkgs[pkg] = (all_pkgs[pkg] || []) + deps
      end
    end

    # Retain only internal dependencies (drop java.*, org.springframework, etc.)
    all_pkg_set = all_pkgs.keys.to_set
    all_pkgs.transform_values! { |deps| deps.select { |d| all_pkg_set.include?(d) }.uniq }

    # Add a synthetic "main" node for any detected entry point classes
    entry_pkgs = detect_main_packages(repo_root, modules)
    if entry_pkgs.any?
      all_pkgs["main"] ||= []
      all_pkgs["main"].concat(entry_pkgs.select { |p| all_pkg_set.include?(p) })
      all_pkgs.delete("main") if all_pkgs["main"].empty?
    end

    all_pkgs
  end

  # ── Build system helpers ──────────────────────────────────────────────────

  def maven_submodule_dirs(pom_path)
    content = File.read(pom_path)
    m = content.match(%r{<modules>(.*?)</modules>}m)
    return [] unless m

    m[1].scan(%r{<module>(.*?)</module>}).flatten.map(&:strip).reject(&:empty?)
  end

  def gradle_includes(settings_path)
    content = File.read(settings_path)
    content.scan(/include\s*[('":]+([^'"):\s,]+)/).flatten.map do |name|
      name.tr(":", "/").delete_prefix("/")
    end.reject(&:empty?)
  end

  # ── Source directory helpers ──────────────────────────────────────────────

  def find_source_dir(mod_dir)
    [
      File.join(mod_dir, "src", "main", "java"),
      File.join(mod_dir, "src", "java"),
      File.join(mod_dir, "src"),
      mod_dir
    ].find { |d| File.directory?(d) }
  end

  # Returns the common Java package prefix (as a "/"-path) for all .java files
  # under src_dir, or nil if no .java files are found.
  def common_java_prefix(src_dir)
    prefixes = []
    Find.find(src_dir) do |path|
      Find.prune if File.directory?(path) && SKIP_DIRS.include?(File.basename(path))
      next unless path.end_with?(".java")

      File.foreach(path) do |line|
        if (m = line.match(/^\s*package\s+([\w.]+)\s*;/))
          prefixes << m[1].split(".")
          break
        end
      end
    end
    return nil if prefixes.empty?

    common = prefixes.first.dup
    prefixes.drop(1).each do |parts|
      common = common.zip(parts).take_while { |a, b| a == b }.map(&:first)
    end
    return nil if common.empty?

    common.join("/")
  end

  # Walk src_dir and return { pkg_path => [import_pkg_paths] } for all packages
  # whose package declaration starts with mod_name (using "/" separators).
  # Packages deeper than MAX_PKG_DEPTH relative levels are folded into their
  # depth-capped ancestor to keep the graph readable.
  def scan_java_packages(src_dir, mod_name)
    pkgs = {}
    Find.find(src_dir) do |path|
      if File.directory?(path)
        Find.prune if SKIP_DIRS.include?(File.basename(path))
        next
      end
      next unless path.end_with?(".java")

      pkg_name = nil
      imports = []
      File.foreach(path) do |line|
        if (m = line.match(/^\s*package\s+([\w.]+)\s*;/))
          pkg_name = cap_depth(m[1].tr(".", "/"), mod_name)
        elsif (m = line.match(/^\s*import\s+(?:static\s+)?([\w.]+(?:\.\*)?)\s*;/))
          imp = strip_class_suffix(m[1].delete_suffix(".*").tr(".", "/"))
          imports << cap_depth(imp, mod_name) unless imp.empty?
        end
      end

      next unless pkg_name
      next unless pkg_name == mod_name || pkg_name.start_with?("#{mod_name}/")

      pkgs[pkg_name] ||= []
      pkgs[pkg_name].concat(imports)
    end

    pkgs.transform_values(&:uniq)
  end

  # Drop trailing path components that begin with an uppercase letter (class names).
  def strip_class_suffix(slash_path)
    parts = slash_path.split("/")
    parts.pop while parts.last&.match?(/\A[A-Z]/)
    parts.join("/")
  end

  # Fold a package path deeper than MAX_PKG_DEPTH (from mod_name) into its
  # depth-capped ancestor. Paths not under mod_name are returned unchanged.
  def cap_depth(pkg, mod_name)
    rel = pkg.delete_prefix("#{mod_name}/")
    return pkg if rel == pkg

    parts = rel.split("/")
    return pkg if parts.length <= MAX_PKG_DEPTH

    "#{mod_name}/#{parts.first(MAX_PKG_DEPTH).join("/")}"
  end

  # Scan source directories for Java entry point classes and return their
  # (depth-capped) package paths. Detects: traditional main methods,
  # @SpringBootApplication, and @QuarkusMain.
  def detect_main_packages(repo_root, modules)
    entry_pkgs = []
    modules.each do |rel_dir, mod_name|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      src = find_source_dir(mod_dir)
      next unless src

      Find.find(src) do |path|
        if File.directory?(path)
          Find.prune if SKIP_DIRS.include?(File.basename(path))
          next
        end
        next unless path.end_with?(".java")

        content = File.read(path, encoding: "utf-8", invalid: :replace)
        next unless content.match?(/public\s+static\s+void\s+main\s*\(/) ||
                    content.match?(/@SpringBootApplication\b/) ||
                    content.match?(/@QuarkusMain\b/)

        if (m = content.match(/^\s*package\s+([\w.]+)\s*;/))
          entry_pkgs << cap_depth(m[1].tr(".", "/"), mod_name)
        end
      end
    end
    entry_pkgs.uniq
  end
end

Archsight::Import::Registry.register("java-grapher", Archsight::Import::Handlers::JavaGrapher)
