# frozen_string_literal: true

require "yaml"
require_relative "../handler"

# Abstract base class for language-specific code-graph import handlers.
#
# Subclasses implement two discovery methods and inherit all graph layout,
# clustering, coloring, and DOT generation logic from here.
#
# Required overrides:
#   discover_modules(repo_root)              → [[rel_dir, mod_name], ...]
#   collect_packages(repo_root, modules, prefix) → {pkg_path => [dep_path, ...]}
#
# Package paths must use "/" as the separator regardless of language so that
# all generic helpers (node_id, short_label, rel_parts, etc.) work correctly.
# Subclasses with "." separators (e.g. Python dotted names) should convert to
# "/" in collect_packages before returning.
#
# Configuration (inherited by all subclasses):
#   import/config/path     - Path to the repository root
#   import/config/ranksep  - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep  - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::Grapher < Archsight::Import::Handler
  # Subclasses declare their language name for explicit --language lookup.
  def self.language_name = nil

  # Subclasses return true when they can handle the given path.
  # Used by Registry.handlers_for to collect all applicable graphers.
  def self.applicable?(_path) = false

  PALETTE = [
    { fill: "#ddeeff", edge: "#2266cc" },
    { fill: "#ddffd8", edge: "#2a8a1e" },
    { fill: "#fff3cc", edge: "#cc8800" },
    { fill: "#fde8e8", edge: "#cc2222" },
    { fill: "#f5e8fd", edge: "#8822cc" },
    { fill: "#fdf5e8", edge: "#cc6600" },
    { fill: "#e8fdfd", edge: "#228888" },
    { fill: "#ffeedd", edge: "#995500" },
    { fill: "#eeeeff", edge: "#4444aa" },
    { fill: "#ffeeff", edge: "#993399" }
  ].freeze

  def execute
    @path = config("path")
    raise "Missing required config: path" unless @path
    raise "Directory not found: #{@path}" unless File.directory?(@path)

    @ranksep = config("ranksep", default: "0.6").to_f
    @nodesep = config("nodesep", default: "0.15").to_f

    progress.update("Discovering modules")
    modules = discover_modules(@path)
    return write_yaml(YAML.dump(self_marker)) if modules.empty?

    module_colors, prefix = build_module_colors(modules)

    progress.update("Collecting packages")
    pkgs = collect_packages(@path, modules, prefix)
    return write_yaml(YAML.dump(self_marker)) if pkgs.empty?

    progress.update("Generating DOT graph")
    dot_content = emit_dot(pkgs, modules, module_colors, prefix,
                           ranksep: @ranksep, nodesep: @nodesep)

    progress.update("Generating resource")
    resource = resource_yaml(
      kind: "TechnologyArtifact",
      name: artifact_name(@path),
      annotations: { annotation_key => dot_content },
      spec: {}
    )

    write_yaml(YAML.dump(resource) + YAML.dump(self_marker))
    write_generates_meta
  end

  def dot_graph(path:, ranksep: 0.6, nodesep: 0.15)
    modules = discover_modules(path)
    return nil if modules.empty?

    module_colors, prefix = build_module_colors(modules)
    pkgs = collect_packages(path, modules, prefix)
    return nil if pkgs.empty?

    emit_dot(pkgs, modules, module_colors, prefix, ranksep: ranksep, nodesep: nodesep)
  end

  private

  def annotation_key
    lang = self.class.language_name
    lang ? "architecture/#{lang}/modules" : "architecture/modules"
  end

  # @abstract Discover modules/packages in the repository.
  # @param repo_root [String] Absolute path to the repository root
  # @return [Array<Array>] List of [rel_dir, mod_name] pairs
  def discover_modules(_repo_root)
    raise NotImplementedError, "#{self.class}#discover_modules must be implemented"
  end

  # @abstract Collect packages and their intra-repo dependencies.
  # @param repo_root [String] Absolute path to the repository root
  # @param modules [Array<Array>] List of [rel_dir, mod_name] pairs from discover_modules
  # @param prefix [String] Common module name prefix (may be empty)
  # @return [Hash] Map of pkg_path => [dep_pkg_path, ...] using "/" separators
  def collect_packages(_repo_root, _modules, _prefix)
    raise NotImplementedError, "#{self.class}#collect_packages must be implemented"
  end

  # ── Module coloring ───────────────────────────────────────────────────────

  def build_module_colors(modules)
    prefix = common_module_prefix(modules.map { |_, m| m })
    colors = {}
    modules.each_with_index do |(rel_dir, mod_name), i|
      label = mod_name.delete_prefix(prefix)
      label = mod_name.split("/").last if label.empty?
      c = PALETTE[i % PALETTE.length]
      colors[rel_dir] = { fill: c[:fill], edge: c[:edge], label: label }
    end
    [colors, prefix]
  end

  def common_module_prefix(module_names)
    return "" if module_names.empty?

    parts = module_names.map { |n| n.split("/") }
    min_len = parts.map(&:length).min
    common = []
    min_len.times do |i|
      column = parts.map { |p| p[i] }
      break unless column.uniq.length == 1

      common << column.first
    end
    common.empty? ? "" : "#{common.join("/")}/"
  end

  def init_node(graph, pkg, mod_name, prefix, cluster_label)
    lbl = short_label(pkg, mod_name)
    if lbl == cluster_label
      if show_root_package_node?
        graph.node(node_id(pkg, prefix), label: "◆")
      else
        graph.node(node_id(pkg, prefix), label: "", style: :invis, width: 0, height: 0)
      end
    else
      graph.node(node_id(pkg, prefix), label: lbl)
    end
  end

  # Hook: return true to render the package node even when its label matches the cluster label.
  # Python/Go leave it false (hide redundant package-root node); Java overrides to true.
  def show_root_package_node?
    false
  end

  def darken(hex_color, factor = 0.88)
    hex = hex_color.delete_prefix("#")
    r = (hex[0, 2].to_i(16) * factor).to_i
    g = (hex[2, 2].to_i(16) * factor).to_i
    b = (hex[4, 2].to_i(16) * factor).to_i
    format("#%02x%02x%02x", r, g, b)
  end

  # ── Node / label helpers ──────────────────────────────────────────────────

  def node_id(pkg_path, prefix)
    pkg_path.delete_prefix(prefix).gsub(/[^a-zA-Z0-9]/, "_")
  end

  def short_label(pkg_path, mod_name)
    rel = pkg_path.delete_prefix("#{mod_name}/")
    rel == pkg_path ? pkg_path.split("/").last : rel
  end

  def rel_parts(pkg_path, mod_name)
    suffix = pkg_path.delete_prefix(mod_name)
    return [] if suffix.empty?

    suffix.delete_prefix("/").split("/")
  end

  def pkg_module_dir(pkg_path, modules, _prefix)
    modules.sort_by { |_, mod_name| -mod_name.length }.each do |rel_dir, mod_name|
      return rel_dir if pkg_path == mod_name || pkg_path.start_with?("#{mod_name}/")
    end
    nil
  end

  # ── Hierarchy ─────────────────────────────────────────────────────────────

  def build_hierarchy_edges(pkg_set)
    edges = []
    pkg_set.each do |pkg|
      parts = pkg.split("/")
      (parts.length - 1).downto(1) do |i|
        parent = parts[0, i].join("/")
        if pkg_set.include?(parent)
          edges << [parent, pkg]
          break
        end
      end
    end
    edges
  end

  # ── Topological depths ────────────────────────────────────────────────────

  def l1_topo_depths(pkgs, mod_name)
    l1_of = {}
    pkgs.each_key do |pkg|
      parts = rel_parts(pkg, mod_name)
      l1_of[pkg] = parts[0] if parts.any? && parts != [""]
    end

    all_l1 = l1_of.values.to_set
    l1_imports = all_l1.to_h { |l1| [l1, Set.new] }

    pkgs.each do |pkg, deps|
      src = l1_of[pkg]
      next unless src

      deps.each do |dep|
        dst = l1_of[dep]
        l1_imports[src] << dst if dst && dst != src
      end
    end

    cache = {}
    depth_fn = lambda { |l1, visiting|
      return cache[l1] if cache.key?(l1)
      return 0 if visiting.include?(l1)

      children = l1_imports[l1] - visiting
      d = children.any? ? 1 + children.map { |c| depth_fn.call(c, visiting | Set[l1]) }.max : 0
      cache[l1] = d
    }
    all_l1.each { |l1| depth_fn.call(l1, Set.new) }

    [cache, l1_imports]
  end

  def module_topo_depths(pkgs, modules)
    pkg_to_dir = {}
    modules.each do |rel_dir, mod_name|
      pkgs.each_key do |pkg|
        pkg_to_dir[pkg] = rel_dir if pkg == mod_name || pkg.start_with?("#{mod_name}/")
      end
    end

    all_dirs = modules.to_set { |rel_dir, _| rel_dir }
    mod_imports = all_dirs.to_h { |d| [d, Set.new] }

    pkgs.each do |pkg, deps|
      src_dir = pkg_to_dir[pkg]
      next unless src_dir

      deps.each do |dep|
        dst_dir = pkg_to_dir[dep]
        mod_imports[src_dir] << dst_dir if dst_dir && dst_dir != src_dir
      end
    end

    cache = {}
    depth_fn = lambda { |d, visiting|
      return cache[d] if cache.key?(d)
      return 0 if visiting.include?(d)

      children = mod_imports[d] - visiting
      v = children.any? ? 1 + children.map { |c| depth_fn.call(c, visiting | Set[d]) }.max : 0
      cache[d] = v
    }
    all_dirs.each { |d| depth_fn.call(d, Set.new) }

    [cache, mod_imports]
  end

  # ── Cluster emitters ──────────────────────────────────────────────────────

  def group_by_l1_l2(pkgs_in_mod, mod_name)
    l1_groups = {}
    ungrouped = []

    pkgs_in_mod.each do |pkg|
      parts = rel_parts(pkg, mod_name)
      if parts.empty? || parts == [""]
        ungrouped << pkg
        next
      end
      l1 = parts[0]
      l2 = parts.length >= 2 ? parts[0, 2].join("/") : nil
      l1_groups[l1] ||= {}
      l1_groups[l1][l2] ||= []
      l1_groups[l1][l2] << pkg
    end

    [l1_groups, ungrouped]
  end

  def emit_module_cluster(graph, mod_name, mod_colors, pkgs_in_mod, prefix)
    cluster_id = mod_name.delete_prefix(prefix).gsub(/[^a-zA-Z0-9]/, "_")
    fill = mod_colors[:fill]

    graph.subgraph("cluster_#{cluster_id}",
                   label: mod_colors[:label], style: "rounded,filled", fillcolor: fill,
                   fontname: "Helvetica Bold", fontsize: 13) do |sg|
      l1_groups, ungrouped = group_by_l1_l2(pkgs_in_mod, mod_name)
      ungrouped.each { |pkg| init_node(sg, pkg, mod_name, prefix, mod_colors[:label]) }
      emit_l1_subclusters(sg, l1_groups, cluster_id, darken(fill, 0.93), darken(fill, 0.86),
                          mod_name, prefix, fontsize: 11)
    end
  end

  def emit_l1_subclusters(graph, l1_groups, cluster_id, l1_fill, l2_fill, mod_name, prefix,
                           fontsize: 12)
    l1_groups.keys.sort.each do |l1|
      nil_pkgs = l1_groups[l1][nil] || []
      l2_keys = l1_groups[l1].keys.compact

      if l2_keys.empty?
        nil_pkgs.sort.each { |pkg| graph.node(node_id(pkg, prefix), label: short_label(pkg, mod_name)) }
        next
      end

      l1_cid = "#{cluster_id}_#{l1}".gsub(/[^a-zA-Z0-9]/, "_")
      graph.subgraph("cluster_#{l1_cid}",
                     label: l1, style: "rounded,filled", fillcolor: l1_fill,
                     fontname: "Helvetica", fontsize: fontsize) do |l1g|
        nil_pkgs.sort.each { |pkg| init_node(l1g, pkg, mod_name, prefix, l1) }
        l2_keys.sort.each do |l2|
          emit_l2_subcluster(l1g, l2, "#{cluster_id}_#{l2.gsub("/", "_")}", l2_fill,
                             l1_groups[l1][l2], mod_name, prefix)
        end
      end
    end
  end

  def emit_l2_subcluster(graph, l2_path, l2_cid_raw, l2_fill, pkgs_in_l2, mod_name, prefix)
    if pkgs_in_l2.length == 1
      pkg = pkgs_in_l2.first
      parts = rel_parts(pkg, mod_name)
      lbl = parts.length > 2 ? parts[2..].join("/") : parts.last
      graph.node(node_id(pkg, prefix), label: lbl)
      return
    end

    l2_cid = l2_cid_raw.gsub(/[^a-zA-Z0-9]/, "_")
    l2_label = l2_path.include?("/") ? l2_path.split("/")[1] : l2_path
    graph.subgraph("cluster_#{l2_cid}",
                   label: l2_label, style: "rounded,filled", fillcolor: l2_fill,
                   fontname: "Helvetica", fontsize: 10) do |l2g|
      pkgs_in_l2.sort.each do |pkg|
        parts = rel_parts(pkg, mod_name)
        lbl = parts.length > 2 ? parts[2..].join("/") : parts.last
        l2g.node(node_id(pkg, prefix), label: lbl)
      end
    end
  end

  def emit_clusters_single_module(graph, mod_name, mod_colors, pkgs_in_mod, prefix)
    l1_groups, ungrouped = group_by_l1_l2(pkgs_in_mod, mod_name)
    l1_colors = l1_groups.keys.sort.each_with_index.with_object({}) do |(l1, idx), h|
      h[l1] = PALETTE[idx % PALETTE.length]
    end

    if wrap_single_module?
      cluster_id = mod_name.gsub(/[^a-zA-Z0-9]/, "_")
      graph.subgraph("cluster_#{cluster_id}",
                     label: mod_colors[:label], style: "rounded,filled", fillcolor: mod_colors[:fill],
                     fontname: "Helvetica Bold", fontsize: 13) do |sg|
        ungrouped.each { |pkg| init_node(sg, pkg, mod_name, prefix, mod_colors[:label]) }
        l1_groups.keys.sort.each do |l1|
          c = l1_colors[l1]
          l1_cid = l1.gsub(/[^a-zA-Z0-9]/, "_")
          emit_l1_subclusters(sg, { l1 => l1_groups[l1] }, l1_cid, c[:fill],
                              darken(c[:fill], 0.86), mod_name, prefix)
        end
      end
    else
      ungrouped.each { |pkg| graph.node(node_id(pkg, prefix), label: short_label(pkg, mod_name)) }
      l1_groups.keys.sort.each do |l1|
        c = l1_colors[l1]
        l1_cid = l1.gsub(/[^a-zA-Z0-9]/, "_")
        emit_l1_subclusters(graph, { l1 => l1_groups[l1] }, l1_cid, c[:fill],
                            darken(c[:fill], 0.86), mod_name, prefix)
      end
    end

    l1_colors
  end

  def wrap_single_module?
    false
  end

  # ── DOT generation ────────────────────────────────────────────────────────

  # Choose GraphViz spline style based on graph complexity.
  # curved: best quality, expensive routing — fine for small graphs.
  # ortho:  right-angle edges, much faster for medium graphs.
  # line:   straight lines, fastest — used for large graphs.
  def splines_for(pkgs)
    edge_count = pkgs.values.sum(&:length)
    if edge_count < 80
      :curved
    elsif edge_count < 400
      :ortho
    else
      :line
    end
  end

  def emit_dot(pkgs, modules, module_colors, prefix, ranksep: 0.6, nodesep: 0.15)
    by_dir = modules.each_with_object({}) { |(rel_dir, _), h| h[rel_dir] = [] }
    pkgs.keys.sort.each { |pkg| assign_pkg_to_dir(pkg, modules, prefix, by_dir) }

    Archsight::Graphvis.new("packages",
                            rankdir: :LR, compound: true, splines: splines_for(pkgs),
                            concentrate: true,
                            ranksep: ranksep, nodesep: nodesep,
                            fontname: "Helvetica", fontsize: 10).draw_dot do |graph|
      graph.defaults(:node, fontname: "Helvetica", fontsize: 8, shape: :box,
                            style: "rounded,filled", fillcolor: :white, height: 0.2, width: 0.4)
      graph.defaults(:edge, fontname: "Helvetica", fontsize: 8)
      pkg_edge_color = {}
      if modules.length == 1
        emit_dot_single_module(graph, modules, by_dir, pkgs, prefix, pkg_edge_color, module_colors)
      else
        emit_dot_multi_module(graph, modules, by_dir, pkgs, module_colors, prefix, pkg_edge_color)
      end
      assigned = by_dir.values.flatten.to_set
      pkgs.keys.sort.each do |pkg|
        next if assigned.include?(pkg)

        graph.node(node_id(pkg, prefix), label: pkg.split("/").last)
        pkg_edge_color[pkg] = "#555555"
      end
      emit_dependency_edges(graph, pkgs, pkg_edge_color, prefix)
    end
  end

  def assign_pkg_to_dir(pkg, modules, prefix, by_dir)
    rel_dir = pkg_module_dir(pkg, modules, prefix)
    by_dir[rel_dir] << pkg if rel_dir && by_dir.key?(rel_dir)
  end

  def emit_dot_single_module(graph, modules, by_dir, pkgs, prefix, pkg_edge_color, module_colors)
    rel_dir, mod_name = modules[0]
    mod_colors = module_colors[rel_dir]
    pkgs_in_mod = by_dir[rel_dir] || []
    l1_colors = emit_clusters_single_module(graph, mod_name, mod_colors, pkgs_in_mod, prefix)

    pkgs_in_mod.each do |pkg|
      parts = rel_parts(pkg, mod_name)
      l1 = parts.any? && parts != [""] ? parts[0] : nil
      pkg_edge_color[pkg] = l1_colors[l1][:edge] if l1 && l1_colors[l1]
    end
    emit_l1_constraint_edges(graph, pkgs, mod_name, pkgs_in_mod, prefix)
  end

  def emit_l1_constraint_edges(graph, pkgs, mod_name, pkgs_in_mod, prefix)
    depths, l1_imports = l1_topo_depths(pkgs, mod_name)
    l1_rep = depths.each_with_object({}) do |l1, h|
      pkgs_in_l1 = pkgs_in_mod.select { |p| rel_parts(p, mod_name)[0, 1] == [l1] }.sort
      h[l1] = node_id(pkgs_in_l1.first, prefix) if pkgs_in_l1.any?
    end
    emit_constraint_edges(graph, l1_imports, l1_rep)
  end

  def emit_dot_multi_module(graph, modules, by_dir, pkgs, module_colors, prefix, pkg_edge_color)
    modules.each do |rel_dir, mod_name|
      pkgs_in_mod = by_dir[rel_dir] || []
      next if pkgs_in_mod.empty?

      emit_module_cluster(graph, mod_name, module_colors[rel_dir], pkgs_in_mod, prefix)
      color = module_colors[rel_dir][:edge]
      pkgs_in_mod.each { |pkg| pkg_edge_color[pkg] = color }
    end
    emit_module_constraint_edges(graph, modules, by_dir, pkgs, prefix)
  end

  def emit_module_constraint_edges(graph, modules, by_dir, pkgs, prefix)
    _depths, mod_imports = module_topo_depths(pkgs, modules)
    mod_rep = modules.each_with_object({}) do |(rel_dir, _), h|
      pkgs_in_mod = (by_dir[rel_dir] || []).sort
      h[rel_dir] = node_id(pkgs_in_mod.first, prefix) if pkgs_in_mod.any?
    end
    emit_constraint_edges(graph, mod_imports, mod_rep)
  end

  def emit_constraint_edges(graph, imports, rep)
    imports.each do |src, dsts|
      src_rep = rep[src]
      dsts.each do |dst|
        dst_rep = rep[dst]
        graph.edge(src_rep, dst_rep, style: :invis, constraint: true) if src_rep && dst_rep
      end
    end
  end

  def emit_dependency_edges(graph, pkgs, pkg_edge_color, prefix)
    pkg_set = pkgs.keys.to_set
    has_children = pkg_set.each_with_object(Set.new) do |p, s|
      parts = p.split("/")
      (1...parts.length).each { |i| s << parts[0, i].join("/") }
    end

    pkgs.keys.sort.each do |pkg|
      edge_color = pkg_edge_color[pkg]
      next unless edge_color

      pkgs[pkg].uniq.sort.each do |dep|
        next if dep == pkg
        next if suppress_edge_to?(dep, pkg_set, has_children)

        graph.edge(node_id(pkg, prefix), node_id(dep, prefix), color: edge_color, style: :solid)
      end
    end
  end

  # Hook: return true to suppress the dependency edge to +dep+.
  # Default: suppress edges to any ancestor path (avoids edges to invisible cluster-root nodes).
  # Java overrides to only suppress structural ancestors (not actual packages in pkg_set).
  def suppress_edge_to?(dep, _pkg_set, has_children)
    has_children.include?(dep)
  end

  # ── Artifact name ─────────────────────────────────────────────────────────

  def artifact_name(path)
    git_config = File.join(path, ".git", "config")
    if File.exist?(git_config)
      url_line = File.read(git_config).lines.find { |l| l.include?("url") }
      if url_line
        url = url_line.split("=").last.strip
        name = url.split(":").last.gsub(/\.git$/, "").tr("/", ":")
        return "Repo:#{name}"
      end
    end
    "Repo:#{File.basename(path)}"
  end
end
