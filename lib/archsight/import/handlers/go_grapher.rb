# frozen_string_literal: true

require "json"
require "open3"
require_relative "grapher"
require_relative "go_module_parser"
require_relative "../registry"

# GoGrapher handler - analyses a Go repository and generates a GraphViz DOT
# graph of its module/package structure, stored as architecture/go/modules on
# the TechnologyArtifact so it can be rendered in the frontend.
#
# Also emits one ApplicationComponent per go.mod module, linked to the repo
# artifact via realizedThrough. If OpenAPI spec files are found in a module
# directory, the component gains an exposes relation to the matching interface.
#
# dependsOn relations between components are resolved in a second pass by the
# GoDepResolver handler, which runs after all graphers have seeded the database.
#
# Configuration:
#   import/config/path                 - Path to the Go repository root (go.mod or go.work)
#   import/config/ranksep              - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep              - Vertical gap between nodes in a column (default: 0.15)
#   import/config/interface_visibility - Visibility prefix for detected interfaces (default: Private)
class Archsight::Import::Handlers::GoGrapher < Archsight::Import::Handlers::Grapher
  include Archsight::Import::Handlers::GoModuleParser

  # Directories not scanned for Go packages
  PACKAGE_SKIP_DIRS = %w[vendor testdata node_modules].freeze
  # Packages below these directories are not meant to be imported by other modules
  NON_LIBRARY_DIRS = %w[internal cmd hack tools examples example e2e test tests].freeze
  MAX_ENTRYPOINTS = 10
  IGNORED_BUILD = %r{^(//go:build\s+ignore\b|//\s*\+build\s+ignore\b)}

  OPENAPI_FILENAMES = %w[openapi.yaml openapi.yml openapi.json swagger.yaml swagger.yml swagger.json].freeze
  OPENAPI_SUBDIRS   = %w[api docs spec].freeze

  def self.language_name = "go"

  def self.applicable?(path)
    File.exist?(File.join(path, "go.work")) ||
      File.exist?(File.join(path, "go.mod")) ||
      Dir.glob(File.join(path, "**/go.mod")).any?
  rescue Errno::ELOOP, Errno::ENOTDIR
    false
  end

  private

  def show_root_package_node?
    true
  end

  def suppress_edge_to?(dep, pkg_set, has_children)
    has_children.include?(dep) && !pkg_set.include?(dep)
  end

  # ── Application resources ─────────────────────────────────────────────────

  def additional_resources(path, modules, artifact_name)
    visibility = config("interface_visibility", default: "Private")
    output = +""

    modules.each do |rel_dir, mod_name|
      comp_name = component_name(mod_name)
      next unless comp_name

      mod_dir = rel_dir == "." ? path : File.join(path, rel_dir)
      specs = detect_openapi_specs(mod_dir)
      existing_interfaces = database&.instances_by_kind("ApplicationInterface") || {}
      interface_names = specs.filter_map { |s| interface_name_from_spec(s, visibility: visibility) }
                             .select { |n| existing_interfaces.key?(n) }

      existing = database&.instances_by_kind("ApplicationComponent")&.[](comp_name)
      facts = curated_component_type?(existing) ? {} : component_facts(path, rel_dir, mod_name)

      comp_spec = { "realizedThrough" => { "technologyArtifacts" => [artifact_name] } }
      comp_spec["exposes"] = { "applicationInterfaces" => interface_names } if interface_names.any?

      # Build directly without resource_yaml so the component is not tracked in
      # the generates spec — ApplicationComponents are seed resources the user
      # is expected to keep and refine, not auto-regenerated on each run.
      component = untracked_resource_yaml(
        kind: "ApplicationComponent",
        name: comp_name,
        spec: comp_spec,
        annotations: component_annotations(facts, existing_tags: existing&.annotations&.[]("architecture/tags"))
      )
      output << YAML.dump(component)
    end

    # Emit a GoDepResolver import so dependsOn relations can be resolved in a
    # second pass, after all graphers have run and the database has been reloaded
    # with the full set of ApplicationComponents.
    resolver_name = "Import:GoDepResolver:#{artifact_name.delete_prefix("Repo:")}"
    output << YAML.dump(import_yaml(
                          name: resolver_name,
                          handler: "go-dep-resolver",
                          config: { "path" => path }
                        ))

    output
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    workspace_mode = File.exist?(File.join(repo_root, "go.work"))
    mod_names = modules.map { |_, mod_name| mod_name }
    all_pkgs = {}

    modules.map(&:first).each do |rel_dir|
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

  # ── OpenAPI detection ─────────────────────────────────────────────────────

  # A component type another source set (a person or an earlier import) is kept; this import's own earlier
  # output is regenerated.
  def curated_component_type?(existing)
    return false unless existing&.annotations&.key?("component/type")

    existing.annotations["generated/script"] != import_resource.name
  end

  # Classify a go.mod module from its packages: with `package main` it is an executable, without it a library,
  # and a module with both main packages and importable packages is a module.
  def component_facts(repo_root, rel_dir, _mod_name)
    mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
    mains, libraries = scan_go_packages(mod_dir)
    type = if mains.empty?
             "library"
           elsif libraries.empty?
             "executable"
           else
             "module"
           end

    { type: type,
      tags: %w[ecosystem:go packaging:go-module] + mains.first(MAX_ENTRYPOINTS).map { |dir| "entrypoint:#{dir}" } }
  end

  # @return [Array<Array<String>>] [main package dirs, importable library package dirs], relative to mod_dir
  def scan_go_packages(mod_dir)
    mains = []
    libraries = []

    Find.find(mod_dir) do |path|
      if File.directory?(path)
        Find.prune if path != mod_dir && skip_go_dir?(path)
        next
      end
      next unless go_source?(path)

      name = go_package_name(path)
      next unless name

      dir = File.dirname(path).delete_prefix(mod_dir).delete_prefix("/")
      dir = "." if dir.empty?
      if name == "main"
        mains << dir
      elsif !dir.split("/").intersect?(NON_LIBRARY_DIRS)
        libraries << dir
      end
    end

    [mains.uniq.sort, libraries.uniq.sort]
  end

  # Hidden and vendored directories, and nested modules (they are components of their own)
  def skip_go_dir?(path)
    base = File.basename(path)
    PACKAGE_SKIP_DIRS.include?(base) || base.start_with?(".") || File.exist?(File.join(path, "go.mod"))
  end

  def go_source?(path)
    path.end_with?(".go") && !path.end_with?("_test.go")
  end

  # Package name of a Go file, nil for a file that is excluded from normal builds (`//go:build ignore`)
  def go_package_name(path)
    head = File.foreach(path, encoding: "utf-8").first(40)
    return nil if head.any? { |line| line.match?(IGNORED_BUILD) }

    head.each do |line|
      match = line.match(/\Apackage\s+(\w+)/)
      return match[1] if match
    end
    nil
  rescue SystemCallError, ArgumentError
    nil
  end

  def untracked_resource_yaml(kind:, name:, spec: {}, annotations: {})
    {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => kind,
      "metadata" => {
        "name" => name,
        "annotations" => {
          "generated/script" => import_resource.name,
          "generated/at" => Time.now.utc.iso8601
        }.merge(annotations)
      },
      "spec" => spec
    }
  end

  def detect_openapi_specs(mod_dir)
    candidates = OPENAPI_FILENAMES.map { |f| File.join(mod_dir, f) }
    OPENAPI_SUBDIRS.each do |sub|
      OPENAPI_FILENAMES.each { |f| candidates << File.join(mod_dir, sub, f) }
    end

    candidates.filter_map do |path|
      next unless File.file?(path)

      begin
        content = File.read(path)
        doc = path.end_with?(".json") ? JSON.parse(content) : YAML.safe_load(content)
        doc.is_a?(Hash) ? doc : nil
      rescue StandardError
        nil
      end
    end
  end

  def interface_name_from_spec(spec, visibility: "Private")
    info = spec["info"] || {}
    title = (info["title"] || "").strip
    return nil if title.empty?

    version = (info["version"] || "1.0").to_s
    api_name = title.split(/[\s\-_]/).map(&:capitalize).join
    version_str = version.split(".").first.to_s.sub(/^v/i, "")
    vis = visibility.split("-").map(&:capitalize).join
    "#{vis}:#{api_name}:v#{version_str}:RestAPI"
  end
end

Archsight::Import::Registry.register("go-grapher", Archsight::Import::Handlers::GoGrapher)
