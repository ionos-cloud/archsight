# frozen_string_literal: true

require "json"
require "open3"
require_relative "grapher"
require_relative "../registry"

# PythonGrapher handler - analyses a Python repository and generates a GraphViz
# DOT graph of its package/module structure, stored as architecture/modules on
# the TechnologyArtifact so it can be rendered in the frontend.
#
# Uses static AST analysis (python3 stdlib only — no external Python packages
# required). Package paths are normalised to "/" separators internally so they
# are compatible with the generic Grapher layout engine.
#
# Configuration:
#   import/config/path     - Path to the Python repository root
#   import/config/ranksep  - Horizontal gap between rank columns (default: 0.6)
#   import/config/nodesep  - Vertical gap between nodes in a column (default: 0.15)
class Archsight::Import::Handlers::PythonGrapher < Archsight::Import::Handlers::Grapher
  def self.language_name = "python"

  def self.detect(path)
    return 90 if File.exist?(File.join(path, "__init__.py"))
    return 85 if File.exist?(File.join(path, "pyproject.toml")) ||
                 File.exist?(File.join(path, "setup.py"))
    Dir.glob(File.join(path, "*/__init__.py")).any? ? 60 : 0
  end

  # Inline Python3 script — scans a single package directory with stdlib ast.
  # Argv: <pkg_root_dir> <pkg_name>
  # Stdout: JSON object mapping slash-separated module paths to arrays of deps.
  #
  # "from pkg import name" is resolved to "pkg/name" when that submodule exists
  # on disk, so that intra-package submodule imports produce correct edges.
  PYTHON_SCANNER = <<~PYTHON
    import ast, os, sys, json

    def collect_all_mods(pkg_root, pkg_name):
        mods = set()
        for dirpath, dirs, files in os.walk(pkg_root):
            dirs[:] = sorted(d for d in dirs if d != '__pycache__' and not d.startswith('.'))
            for f in files:
                if not f.endswith('.py'):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, f), pkg_root)
                parts = rel.replace(os.sep, '/').split('/')
                parts[-1] = parts[-1][:-3]
                if parts[-1] == '__init__':
                    parts = parts[:-1]
                elif parts[-1] == '__main__':
                    parts[-1] = 'main'
                mods.add(pkg_name if not parts else pkg_name + '/' + '/'.join(parts))
        return mods

    def mod_from_path(path, pkg_root, pkg_name):
        rel = os.path.relpath(path, pkg_root)
        parts = rel.replace(os.sep, '/').split('/')
        parts[-1] = parts[-1][:-3]
        if parts[-1] == '__init__':
            parts = parts[:-1]
        elif parts[-1] == '__main__':
            parts[-1] = 'main'
        return pkg_name if not parts else pkg_name + '/' + '/'.join(parts)

    def resolve_relative_base(current_mod, level, module_name):
        """Resolve a relative import to an absolute slash-path.

        level=1 means same package (go up one component from the module name),
        level=2 means parent package, etc.
        """
        parts = current_mod.split('/')
        # Strip `level` trailing components to get the anchor package
        base_parts = parts[:-level] if level <= len(parts) else []
        if module_name:
            base_parts = base_parts + module_name.replace('.', '/').split('/')
        return '/'.join(base_parts) if base_parts else None

    def resolve_from_import(base, names, all_mods):
        resolved = []
        for alias in names:
            sub = base + '/' + alias.name
            resolved.append(sub if sub in all_mods else base)
        return resolved or [base]

    def scan_imports(path, current_mod, pkg_name, all_mods):
        try:
            tree = ast.parse(open(path, encoding='utf-8', errors='replace').read())
        except SyntaxError:
            return []
        out = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    name = alias.name.replace('.', '/')
                    if name == pkg_name or name.startswith(pkg_name + '/'):
                        out.append(name)
            elif isinstance(node, ast.ImportFrom):
                if node.level == 0:
                    if node.module is None:
                        continue
                    base = node.module.replace('.', '/')
                else:
                    base = resolve_relative_base(current_mod, node.level, node.module)
                    if base is None:
                        continue
                if base == pkg_name or base.startswith(pkg_name + '/'):
                    out.extend(resolve_from_import(base, node.names, all_mods))
        return out

    def is_trivial_init(path):
        """True if __init__.py has no function/class defs and no non-dunder assignments."""
        try:
            tree = ast.parse(open(path, encoding='utf-8', errors='replace').read())
        except SyntaxError:
            return True
        for node in ast.iter_child_nodes(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                return False
            if isinstance(node, ast.Assign):
                targets = [t.id for t in node.targets if isinstance(t, ast.Name)]
                if any(not t.startswith('__') for t in targets):
                    return False
        return True

    pkg_root, pkg_name = sys.argv[1], sys.argv[2]
    all_mods = collect_all_mods(pkg_root, pkg_name)
    edges = {}
    init_file_mods = {}
    for dirpath, dirs, files in os.walk(pkg_root):
        dirs[:] = sorted(d for d in dirs if d != '__pycache__' and not d.startswith('.'))
        for f in files:
            if not f.endswith('.py'):
                continue
            p = os.path.join(dirpath, f)
            mod = mod_from_path(p, pkg_root, pkg_name)
            if f == '__init__.py':
                init_file_mods[mod] = p
            imps = scan_imports(p, mod, pkg_name, all_mods)
            if mod not in edges:
                edges[mod] = []
            edges[mod].extend(i for i in imps if i != mod)
    for mod, fpath in init_file_mods.items():
        if not edges.get(mod) and is_trivial_init(fpath):
            edges.pop(mod, None)
    print(json.dumps(edges))
  PYTHON

  # Scans a list of root-level Python scripts for imports from known packages.
  # Argv[1]: JSON {"paths": [...], "packages": [...], "all_mods": [...]}
  # Stdout:  JSON {"<pkg>/main": ["<dep>", ...]}
  ROOT_SCANNER = <<~PYTHON
    import ast, sys, json

    def extract_imports(path, pkg_names, all_mods):
        try:
            tree = ast.parse(open(path, encoding='utf-8', errors='replace').read())
        except (SyntaxError, OSError):
            return []
        out = []
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    base = alias.name.replace('.', '/')
                    if any(base == p or base.startswith(p + '/') for p in pkg_names):
                        out.append(base)
            elif isinstance(node, ast.ImportFrom):
                if node.level == 0 and node.module:
                    base = node.module.replace('.', '/')
                    if any(base == p or base.startswith(p + '/') for p in pkg_names):
                        sub = base + '/' + node.names[0].name if node.names else base
                        out.append(sub if sub in all_mods else base)
        return list(dict.fromkeys(out))

    cfg = json.loads(sys.argv[1])
    pkg_names = cfg['packages']
    all_mods = set(cfg.get('all_mods', []))
    result = {}
    for path in cfg['paths']:
        deps = extract_imports(path, pkg_names, all_mods)
        if not deps:
            continue
        main_pkg = next((p for dep in deps for p in pkg_names if dep == p or dep.startswith(p + '/')), None)
        if not main_pkg:
            continue
        result['main'] = list(dict.fromkeys(result.get('main', []) + deps))
    print(json.dumps(result))
  PYTHON

  def wrap_single_module?
    true
  end

  SKIP_DIRS = %w[test tests docs doc examples example vendor .git __pycache__ dist build
                 node_modules .tox .venv venv env].freeze

  private

  # ── Module discovery ─────────────────────────────────────────────────────

  def discover_modules(repo_root)
    # If the root itself is a Python package, treat it as a single module.
    if File.exist?(File.join(repo_root, "__init__.py"))
      return [[".", File.basename(repo_root)]]
    end

    modules = []
    Dir.each_child(repo_root) do |entry|
      next if SKIP_DIRS.include?(entry) || entry.start_with?(".")
      dir = File.join(repo_root, entry)
      next unless File.directory?(dir) && File.exist?(File.join(dir, "__init__.py"))

      modules << [entry, entry]
    end

    modules.sort_by { |rel, _| rel }
  end

  # ── Package collection ────────────────────────────────────────────────────

  def collect_packages(repo_root, modules, _prefix)
    all_pkgs = {}

    modules.each do |rel_dir, mod_name|
      mod_dir = rel_dir == "." ? repo_root : File.join(repo_root, rel_dir)
      out, err, status = Open3.capture3("python3", "-c", PYTHON_SCANNER, mod_dir, mod_name)

      unless status.success?
        progress.warn("Skipping #{rel_dir}: #{err.lines.first.to_s.strip}")
        next
      end

      JSON.parse(out).each do |pkg, deps|
        all_pkgs[pkg] ||= []
        all_pkgs[pkg].concat(deps)
      end
    end

    root_scripts = find_root_python_scripts(repo_root)
    if root_scripts.any?
      pkg_names = modules.map { |_, mod_name| mod_name }
      config = { "paths" => root_scripts, "packages" => pkg_names,
                 "all_mods" => all_pkgs.keys }.to_json
      out, _err, status = Open3.capture3("python3", "-c", ROOT_SCANNER, config)
      if status.success?
        JSON.parse(out).each do |pkg, deps|
          all_pkgs[pkg] ||= []
          all_pkgs[pkg].concat(deps)
        end
      end
    end

    all_pkgs
  end

  def find_root_python_scripts(repo_root)
    Dir.each_child(repo_root).filter_map do |f|
      path = File.join(repo_root, f)
      next unless File.file?(path) && !f.end_with?(".py")

      begin
        first_line = File.open(path, &:readline).strip
        path if first_line.match?(/python/)
      rescue StandardError
        nil
      end
    end
  end
end

Archsight::Import::Registry.register("python-grapher", Archsight::Import::Handlers::PythonGrapher)
