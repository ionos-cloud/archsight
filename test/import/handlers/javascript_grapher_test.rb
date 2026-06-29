# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/handlers/javascript_grapher"
require "archsight/import/progress"

class JavaScriptGrapherTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  # ── Single module — ES modules ────────────────────────────────────────────

  def test_single_module_src_layout_generates_dot
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "src/components/Button.ts", "import { helper } from '../utils/helper'")
      write(repo, "src/utils/helper.ts", "")

      dot = run_grapher(repo)

      assert_includes dot, "digraph"
      assert_match(/components/, dot)
      assert_match(/utils/, dot)
    end
  end

  def test_dependency_edge_from_es_import
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "src/components/Button.ts", "import { helper } from '../utils/helper'")
      write(repo, "src/utils/helper.ts", "")

      dot = run_grapher(repo)

      assert_match(/"components"\s*->\s*"utils"/, dot)
    end
  end

  def test_export_from_creates_edge
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "src/api/index.ts", "export { foo } from '../services/api'")
      write(repo, "src/services/api.ts", "")

      dot = run_grapher(repo)

      assert_match(/"api"\s*->\s*"services"/, dot)
    end
  end

  # ── Single module — CommonJS ──────────────────────────────────────────────

  def test_dependency_edge_from_commonjs_require
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "src/routes/users.js", "const db = require('../db/client')")
      write(repo, "src/db/client.js", "")

      dot = run_grapher(repo)

      assert_match(/"routes"\s*->\s*"db"/, dot)
    end
  end

  def test_lib_layout_used_when_no_src
    with_repo do |repo|
      write(repo, "package.json", json(name: "mylib"))
      write(repo, "lib/core/index.js", "const utils = require('./utils')")
      write(repo, "lib/core/utils.js", "")

      dot = run_grapher(repo)

      assert_includes dot, "digraph"
      assert_match(/core/, dot)
    end
  end

  # ── type-only imports ─────────────────────────────────────────────────────

  def test_import_type_produces_no_edge
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "src/components/Button.ts",
            "import type { ButtonProps } from '../types/props'\nimport { helper } from '../utils/helper'")
      write(repo, "src/types/props.ts", "")
      write(repo, "src/utils/helper.ts", "")

      dot = run_grapher(repo)

      refute_match(/"components"\s*->\s*"types"/, dot)
      assert_match(/"components"\s*->\s*"utils"/, dot)
    end
  end

  # ── Excluded directories ──────────────────────────────────────────────────

  def test_node_modules_excluded
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "src/app.ts", "")
      write(repo, "node_modules/lodash/index.js", "")

      dot = run_grapher(repo)

      refute_includes dot, "lodash"
    end
  end

  def test_dist_excluded
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "src/app.ts", "")
      write(repo, "dist/app.js", "")

      dot = run_grapher(repo)

      refute_match(/"dist"/, dot)
    end
  end

  def test_test_directory_excluded
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "src/services/api.ts", "")
      write(repo, "src/__tests__/api.test.ts", "import { api } from '../services/api'")

      dot = run_grapher(repo)

      refute_match(/__tests__/, dot)
    end
  end

  # ── Deep file capping ─────────────────────────────────────────────────────

  def test_deep_directories_capped_at_max_depth
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "src/services/auth/providers/google.ts", "")
      write(repo, "src/services/auth/providers/github.ts", "")

      dot = run_grapher(repo)

      refute_match(/"providers"/, dot)
      assert_match(/services/, dot)
    end
  end

  # ── tsconfig path aliases ─────────────────────────────────────────────────

  def test_tsconfig_alias_resolves_to_internal_package
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "tsconfig.json", JSON.generate(
                                     "compilerOptions" => {
                                       "baseUrl" => ".",
                                       "paths" => { "@/*" => ["src/*"] }
                                     }
                                   ))
      write(repo, "src/components/Button.ts", "import { helper } from '@/utils/helper'")
      write(repo, "src/utils/helper.ts", "")

      dot = run_grapher(repo)

      assert_match(/"components"\s*->\s*"utils"/, dot)
    end
  end

  def test_tsconfig_named_alias_resolves
    with_repo do |repo|
      write(repo, "package.json", json(name: "myapp"))
      write(repo, "tsconfig.json", JSON.generate(
                                     "compilerOptions" => {
                                       "baseUrl" => ".",
                                       "paths" => { "@services/*" => ["src/services/*"] }
                                     }
                                   ))
      write(repo, "src/api/handler.ts", "import { client } from '@services/http'")
      write(repo, "src/services/http.ts", "")

      dot = run_grapher(repo)

      assert_match(/"api"\s*->\s*"services"/, dot)
    end
  end

  # ── NPM workspaces ────────────────────────────────────────────────────────

  def test_npm_workspaces_discover_multiple_modules
    with_repo do |repo|
      write(repo, "package.json", json(name: "monorepo", workspaces: ["packages/*"]))
      write(repo, "packages/api/package.json", json(name: "@mono/api"))
      write(repo, "packages/api/src/routes/users.ts", "")
      write(repo, "packages/shared/package.json", json(name: "@mono/shared"))
      write(repo, "packages/shared/src/utils/index.ts", "")

      dot = run_grapher(repo)
      # Base grapher strips the common "@mono/" prefix from labels; check packages instead
      assert_includes dot, "cluster"
      assert_match(/routes/, dot)
      assert_match(/utils/, dot)
    end
  end

  def test_cross_workspace_import_creates_edge
    with_repo do |repo|
      write(repo, "package.json", json(name: "monorepo", workspaces: ["packages/*"]))
      write(repo, "packages/api/package.json", json(name: "@mono/api"))
      write(repo, "packages/api/src/handler.ts", "import { helper } from '@mono/shared'")
      write(repo, "packages/shared/package.json", json(name: "@mono/shared"))
      write(repo, "packages/shared/src/index.ts", "")

      dot = run_grapher(repo)

      assert_match(%r{@mono/api.*->.*@mono/shared|api.*->.*shared}, dot)
    end
  end

  # ── PNPM workspaces ───────────────────────────────────────────────────────

  def test_pnpm_workspace_discovers_packages
    with_repo do |repo|
      write(repo, "package.json", json(name: "root"))
      write(repo, "pnpm-workspace.yaml", "packages:\n  - 'packages/*'\n")
      write(repo, "packages/core/package.json", json(name: "core"))
      write(repo, "packages/core/src/index.ts", "")

      dot = run_grapher(repo)

      assert_includes dot, "digraph"
      assert_includes dot, "core"
    end
  end

  # ── No JS files ───────────────────────────────────────────────────────────

  def test_no_js_files_writes_self_marker_only
    with_repo do |repo|
      write(repo, "package.json", json(name: "empty"))
      write(repo, "README.md", "# hello")

      output = run_full_handler(repo)
      resources = YAML.load_stream(output)

      assert_equal(["Import"], resources.map { |r| r["kind"] })
    end
  end

  # ── Error cases ───────────────────────────────────────────────────────────

  def test_missing_path_raises_error
    handler = create_handler(path: nil)
    assert_raises(RuntimeError) { handler.execute }
  end

  def test_nonexistent_path_raises_error
    handler = create_handler(path: "/nonexistent/path/does/not/exist")
    assert_raises(RuntimeError) { handler.execute }
  end

  private

  def write(base, rel_path, content)
    full = File.join(base, rel_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def json(**fields)
    JSON.generate(fields.transform_keys(&:to_s))
  end

  def with_repo
    repo = Dir.mktmpdir
    yield repo
  ensure
    FileUtils.rm_rf(repo)
  end

  def create_handler(path:)
    annotations = { "import/handler" => "javascript-grapher" }
    annotations["import/config/path"] = path if path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:JavaScriptGrapher:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockJavaScriptImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::JavaScriptGrapher.new(
      import_resource,
      database: nil,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def output_path
    File.join(@resources_dir, "generated", "Import_JavaScriptGrapher_test.yaml")
  end

  def run_full_handler(path)
    handler = create_handler(path: path)
    handler.execute
    File.read(output_path)
  end

  def run_grapher(path)
    output = run_full_handler(path)
    resources = YAML.load_stream(output)
    artifact = resources.find { |r| r["kind"] == "TechnologyArtifact" }
    artifact&.dig("metadata", "annotations", "architecture/javascript/modules") || ""
  end

  class MockJavaScriptImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/javascript-grapher-test.yaml")
    end
  end
end
