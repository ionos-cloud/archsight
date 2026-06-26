# frozen_string_literal: true

require "open3"
require "find"
require_relative "grapher"
require_relative "../registry"

# GoGrapher handler - analyses a Go repository and generates a GraphViz DOT
# graph of its module/package structure, stored as architecture/modules on
# the TechnologyArtifact so it can be rendered in the frontend.
#
# Configuration:
#   import/config/path     - Path to the Go repository root (go.mod or go.work)
#   import/config/ranksep  - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep  - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::GoGrapher < Archsight::Import::Handlers::Grapher
  def self.language_name = "go"

  def self.detect(path)
    return 95 if File.exist?(File.join(path, "go.work"))
    return 90 if File.exist?(File.join(path, "go.mod"))
    Dir.glob(File.join(path, "**/go.mod")).any? ? 50 : 0
  end

  private

  def show_root_package_node?
    true
  end

  def suppress_edge_to?(dep, pkg_set, has_children)
    has_children.include?(dep) && !pkg_set.include?(dep)
  end

  # ── Module discovery ─────────────────────────────────────────────────────

  def discover_modules(repo_root)
    work_file = File.join(repo_root, "go.work")
    modules = []

    if File.exist?(work_file)
      content = File.read(work_file)
      dirs = if (block_match = content.match(/\buse\s*\((.*?)\)/m))
               block_match[1].split.map(&:strip).reject(&:empty?)
             else
               content.scan(/\buse\s+(\S+)/).flatten
             end
      dirs.each do |d|
        rel = d == "." ? "" : d.delete_prefix("./")
        abs_dir = rel.empty? ? repo_root : File.join(repo_root, rel)
        mod_name = read_module_name(abs_dir)
        modules << [rel.empty? ? "." : rel, mod_name] if mod_name
      end
    else
      mod_name = read_module_name(repo_root)
      if mod_name
        modules << [".", mod_name]
      else
        # No root go.mod: scan subdirectories for go.mod files (monorepo without go.work)
        Find.find(repo_root) do |path|
          bn = File.basename(path)
          Find.prune if File.directory?(path) && %w[vendor testdata .git node_modules].include?(bn)
          next unless bn == "go.mod"
          mod_dir = File.dirname(path)
          rel = mod_dir.delete_prefix("#{repo_root}/")
          name = read_module_name(mod_dir)
          modules << [rel, name] if name
        end
      end
    end

    modules
  end

  def read_module_name(mod_dir)
    gomod = File.join(mod_dir, "go.mod")
    return nil unless File.exist?(gomod)

    File.foreach(gomod) do |line|
      m = line.match(/^\s*module\s+(\S+)/)
      return m[1] if m
    end
    nil
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    workspace_mode = File.exist?(File.join(repo_root, "go.work"))
    mod_names = modules.map { |_, mod_name| mod_name }
    all_pkgs = {}

    modules.each do |rel_dir, _|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      cmd = ["go", "list", "-e", "-f", "{{.ImportPath}}|||{{join .Imports \" \"}}", "./..."]
      cmd.insert(2, "-mod=vendor") if File.directory?(File.join(mod_dir, "vendor"))
      cmd.insert(2, "-mod=readonly") unless workspace_mode || cmd.include?("-mod=vendor")
      out, err, status = Open3.capture3(*cmd, chdir: mod_dir)

      unless status.success?
        progress.warn("Skipping #{rel_dir}: #{err.lines.first.to_s.strip}")
        next
      end

      out.each_line do |line|
        next unless line.include?("|||")

        pkg, _, imports_str = line.partition("|||")
        pkg = pkg.strip
        next if pkg.include?("testdata") || pkg.start_with?("_")
        next unless mod_names.any? { |m| pkg == m || pkg.start_with?("#{m}/") }

        internal_imports = imports_str.split.reject { |i| i.include?("testdata") }.select do |i|
          mod_names.any? { |m| i == m || i.start_with?("#{m}/") }
        end
        all_pkgs[pkg] = internal_imports
      end
    end

    all_pkgs
  end
end

Archsight::Import::Registry.register("go-grapher", Archsight::Import::Handlers::GoGrapher)
