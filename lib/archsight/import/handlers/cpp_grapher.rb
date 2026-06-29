# frozen_string_literal: true

require "find"
require_relative "grapher"
require_relative "../registry"

# CppGrapher — analyses a C/C++ repository and generates a GraphViz DOT graph
# of its directory/module structure, stored as architecture/cpp/modules on the
# TechnologyArtifact.
#
# C/C++ has no formal module system, so directory structure is the de facto
# module boundary. Quoted #include "..." statements express local dependencies;
# angled #include <...> are system/external headers and are ignored.
#
# Supports single-project and multi-project (CMake add_subdirectory) layouts.
# Pure static regex analysis — no compiler or CMake required.
#
# File-to-package mapping:
#   src/engine/core.cpp   → project/engine/core → capped → project/engine
#   include/engine/core.h → project/engine/core → capped → project/engine
#   src/renderer.cpp      → project/renderer (depth 1, not capped)
#   main.cpp              → dep extraction skipped (entry point)
#
# Configuration:
#   import/config/path    - Path to the C/C++ repository root
#   import/config/ranksep - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::CppGrapher < Archsight::Import::Handlers::Grapher
  def self.language_name = "cpp"

  def self.applicable?(path)
    File.exist?(File.join(path, "CMakeLists.txt")) ||
      File.exist?(File.join(path, "meson.build")) ||
      Dir.glob(File.join(path, "*.{cpp,c,cc,cxx,h,hpp}")).any? ||
      Dir.glob(File.join(path, "src/*.{cpp,c,cc,cxx}")).any? ||
      Dir.glob(File.join(path, "include/*.{h,hpp,hh}")).any?
  end

  def wrap_single_module?
    true
  end

  SKIP_DIRS = %w[build .build out .git third_party extern external vendor test tests
                 googletest gtest CMakeFiles cmake .cache _deps generated].freeze
  MAX_PKG_DEPTH = 2
  SOURCE_EXTS = %w[.cpp .c .cc .cxx .h .hpp .hh .hxx].freeze
  SRC_PREFIXES = %w[src/ include/ lib/ source/].freeze
  INCLUDE_RE = /^\s*#\s*include\s+"([^"]+)"/
  ENTRY_FILES = %w[main.cpp main.c Main.cpp Main.c].freeze
  EXT_RE = /\.(cpp|c|cc|cxx|hpp|h|hh|hxx)\z/

  private

  # ── Module discovery ─────────────────────────────────────────────────────

  def discover_modules(repo_root)
    cmake_sub_modules(repo_root) ||
      [[".", cmake_project_name(repo_root) || File.basename(repo_root)]]
  end

  def cmake_sub_modules(repo_root)
    cmake = File.join(repo_root, "CMakeLists.txt")
    return nil unless File.exist?(cmake)

    content = File.read(cmake, encoding: "utf-8")
    dirs = content.scan(/^\s*add_subdirectory\s*\(\s*([^\s)]+)/).flatten
    return nil if dirs.empty?

    modules = dirs.filter_map do |dir|
      abs = File.join(repo_root, dir)
      next unless File.directory?(abs)

      mod_name = cmake_project_name(abs) || dir.gsub(/[^a-zA-Z0-9]/, "_").downcase
      [dir, mod_name]
    end
    modules.any? ? modules : nil
  end

  def cmake_project_name(dir)
    cmake = File.join(dir, "CMakeLists.txt")
    return nil unless File.exist?(cmake)

    content = File.read(cmake, encoding: "utf-8")
    m = content.match(/^\s*project\s*\(\s*([^\s)]+)/i)
    return nil unless m

    m[1].gsub(/[^a-zA-Z0-9]/, "_").downcase
  rescue StandardError
    nil
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    all_pkgs = {}
    file_registry = build_file_registry(repo_root, modules)
    scan_all_sources(repo_root, modules, file_registry, all_pkgs)
    pkg_set = all_pkgs.keys.to_set
    all_pkgs.each_value { |deps| deps.select! { |d| pkg_set.include?(d) } }
    all_pkgs
  end

  def build_file_registry(repo_root, modules)
    file_registry = {}
    modules.each do |rel_dir, mod_name|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      register_files(mod_dir, mod_name, file_registry)
    end
    file_registry
  end

  def scan_all_sources(repo_root, modules, file_registry, all_pkgs)
    modules.each do |rel_dir, mod_name|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      scan_sources(mod_dir, mod_name, file_registry, all_pkgs)
    end
  end

  # ── File registry ─────────────────────────────────────────────────────────

  # Registers multiple lookup keys per file so that both full-path includes
  # (#include "engine/core.h") and short-form includes (#include "core.h")
  # resolve to the correct package. First registration wins to avoid ambiguity
  # when the same basename appears in multiple directories.
  def register_files(mod_dir, mod_name, file_registry)
    Find.find(mod_dir) do |path|
      if File.directory?(path)
        Find.prune if SKIP_DIRS.include?(File.basename(path))
        next
      end
      next unless SOURCE_EXTS.include?(File.extname(path))

      pkg = cap_depth(file_to_pkg(path, mod_dir, mod_name), mod_name)
      rel_parts = path.delete_prefix("#{mod_dir}/").split("/")
      rel_parts.length.times do |i|
        file_registry[rel_parts[i..].join("/")] ||= pkg
      end
    end
  end

  # ── Source scanning ───────────────────────────────────────────────────────

  def scan_sources(mod_dir, mod_name, file_registry, all_pkgs)
    Find.find(mod_dir) do |path|
      if File.directory?(path)
        Find.prune if SKIP_DIRS.include?(File.basename(path))
        next
      end
      next unless SOURCE_EXTS.include?(File.extname(path))

      pkg = cap_depth(file_to_pkg(path, mod_dir, mod_name), mod_name)
      all_pkgs[pkg] ||= []

      # main.cpp / main.c are entry points — skipping their deps avoids a
      # hub-spoke pattern where every module fans out from the invisible root.
      next if ENTRY_FILES.include?(File.basename(path))

      extract_includes(path, file_registry).each do |dep|
        next if dep == pkg || all_pkgs[pkg].include?(dep)

        all_pkgs[pkg] << dep
      end
    end
  end

  def extract_includes(path, file_registry)
    deps = []
    File.foreach(path, encoding: "utf-8") do |line|
      m = line.match(INCLUDE_RE)
      next unless m

      dep = file_registry[m[1]]
      deps << dep if dep
    end
    deps.uniq
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    []
  end

  # ── Package path helpers ──────────────────────────────────────────────────

  # Maps a source/header file to its package path. Standard source directory
  # prefixes (src/, include/, lib/, source/) are stripped so that files in
  # separate src/ and include/ trees map to the same package hierarchy.
  def file_to_pkg(abs_path, mod_dir, mod_name)
    rel = abs_path.delete_prefix("#{mod_dir}/").sub(EXT_RE, "")
    SRC_PREFIXES.each do |p|
      if rel.start_with?(p)
        rel = rel.delete_prefix(p)
        break
      end
    end
    return mod_name if rel.empty?
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

Archsight::Import::Registry.register("cpp-grapher", Archsight::Import::Handlers::CppGrapher)
