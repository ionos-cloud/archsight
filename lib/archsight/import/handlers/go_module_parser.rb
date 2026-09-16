# frozen_string_literal: true

require "find"

# Shared Go module parsing utilities included by GoGrapher and GoDepResolver.
#
# Provides go.mod discovery, module name reading, require parsing, and the
# component_name convention (strip SCM host, join path segments with ":").
module Archsight::Import::Handlers::GoModuleParser
  # Discover all Go modules in a repository root.
  # Handles go.work workspaces, single-module repos, and multi-module monorepos
  # (root go.mod plus subdirectory go.mod files without go.work).
  #
  # @param repo_root [String] Absolute path to the repository root
  # @return [Array<Array<String>>] List of [rel_dir, mod_name] pairs
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
      root_mod = read_module_name(repo_root)
      modules << [".", root_mod] if root_mod
      modules.concat(discover_nested_modules(repo_root, root_mod))
    end

    modules
  end

  # Scan subdirectories for additional go.mod files (multi-module monorepo
  # without go.work). Skips a nested go.mod whose declared module path is
  # unrelated to the repo's own root module - likely a vendored/embedded copy
  # of a foreign project (e.g. a full committed snapshot of another,
  # possibly since-renamed, repo) rather than an intentional submodule of
  # this one - so it doesn't manufacture a cross-repo component/dependency.
  #
  # @return [Array<Array<String>>] List of [rel_dir, mod_name] pairs
  def discover_nested_modules(repo_root, root_mod)
    modules = []

    Find.find(repo_root) do |path|
      bn = File.basename(path)
      Find.prune if File.directory?(path) && %w[vendor testdata .git node_modules].include?(bn)
      next unless bn == "go.mod"

      mod_dir = File.dirname(path)
      next if mod_dir == repo_root # already added above

      rel = mod_dir.delete_prefix("#{repo_root}/")
      name = read_module_name(mod_dir)
      next unless name

      if root_mod && !nested_under_root?(name, root_mod)
        progress.warn("Skipping foreign nested go.mod at #{rel}: module #{name} is unrelated to root module #{root_mod}")
        next
      end

      modules << [rel, name]
    end

    modules
  end

  # Read the module name declared in go.mod.
  # @return [String, nil] Module path or nil if go.mod absent / no module line
  def read_module_name(mod_dir)
    gomod = File.join(mod_dir, "go.mod")
    return nil unless File.exist?(gomod)

    File.foreach(gomod) do |line|
      m = line.match(/^\s*module\s+(\S+)/)
      return m[1] if m
    end
    nil
  end

  # Parse require directives from go.mod, handling both block and single-line forms.
  # @return [Array<String>] Unique module paths listed in require directives
  def go_mod_requires(mod_dir)
    gomod = File.join(mod_dir, "go.mod")
    return [] unless File.exist?(gomod)

    content = File.read(gomod)
    paths = []

    # Block form: require ( ... )
    content.scan(/\brequire\s*\(([^)]*)\)/m) do |block|
      block[0].each_line do |line|
        stripped = line.strip.split("//").first&.strip
        mod_path = stripped&.split&.first
        paths << mod_path if mod_path && !mod_path.empty?
      end
    end

    # Single-line form: require module/path vX.Y.Z (strip block forms first to avoid double-counting)
    content.gsub(/\brequire\s*\([^)]*\)/m, "").scan(/^\s*require\s+(\S+)/) do |m|
      paths << m[0]
    end

    paths.uniq
  end

  # Whether a nested module's declared path is the root module itself or
  # genuinely nested under it (a real monorepo submodule), as opposed to an
  # unrelated/foreign module path (a vendored or embedded copy of another
  # project) that happens to live in a subdirectory.
  # @return [Boolean]
  def nested_under_root?(mod_name, root_mod_name)
    mod_name == root_mod_name || mod_name.start_with?("#{root_mod_name}/")
  end

  # Return the SCM host+org prefix shared by modules in the same org, e.g. "github.com/ionos-cloud/".
  # @return [String, nil] Prefix with trailing slash, or nil for single-segment names
  def same_origin_prefix(mod_name)
    parts = mod_name.split("/")
    return nil if parts.length < 2

    "#{parts[0, 2].join("/")}/"
  end

  # Convert a Go module path to an ApplicationComponent name.
  # Strips the SCM host segment and joins remaining path segments with ":".
  # "github.com/ionos-cloud/event-gateway/pkg" → "ionos-cloud:event-gateway:pkg"
  def component_name(mod_name)
    parts = mod_name.split("/")
    parts.shift
    parts.join(":")
  end
end
