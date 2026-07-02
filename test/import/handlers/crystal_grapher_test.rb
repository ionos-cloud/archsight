# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/handlers/crystal_grapher"
require "archsight/import/progress"

class CrystalGrapherTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  # ── Single shard ──────────────────────────────────────────────────────────

  def test_single_shard_generates_dot_graph
    with_repo do |repo|
      write(repo, "shard.yml", shard_yml("my_shard"))
      write(repo, "src/my_shard/core.cr", "")
      write(repo, "src/my_shard/utils.cr", "")

      dot = run_grapher(repo)

      assert_includes dot, "digraph"
      assert_match(/core|utils/, dot)
    end
  end

  # ── Dependency edges ──────────────────────────────────────────────────────

  def test_dependency_edge_from_relative_require
    with_repo do |repo|
      write(repo, "shard.yml", shard_yml("my_shard"))
      write(repo, "src/my_shard/web.cr", 'require "./models/user"')
      write(repo, "src/my_shard/models/user.cr", "")

      dot = run_grapher(repo)
      # node IDs strip common "my_shard/" prefix; "/" → "_"
      assert_match(/"web"\s*->\s*"models"/, dot)
    end
  end

  def test_dependency_edge_from_upward_require
    with_repo do |repo|
      write(repo, "shard.yml", shard_yml("my_shard"))
      write(repo, "src/my_shard/web/router.cr", 'require "../db"')
      write(repo, "src/my_shard/db.cr", "")

      dot = run_grapher(repo)
      # web/router is depth 3 → capped to my_shard/web (MAX_PKG_DEPTH=2); node ID = "web"
      assert_match(/"web"\s*->\s*"db"/, dot)
    end
  end

  def test_absolute_require_produces_no_edge
    with_repo do |repo|
      write(repo, "shard.yml", shard_yml("my_shard"))
      write(repo, "src/my_shard/app.cr", 'require "kemal"')
      write(repo, "src/my_shard/other.cr", "")

      dot = run_grapher(repo)

      refute_match(/kemal/, dot)
    end
  end

  # ── Directory require convention ──────────────────────────────────────────

  def test_directory_require_resolves_index_file
    with_repo do |repo|
      write(repo, "shard.yml", shard_yml("my_shard"))
      # require "./models" resolves to models/models.cr (Crystal directory convention)
      write(repo, "src/my_shard/app.cr", 'require "./models"')
      write(repo, "src/my_shard/models/models.cr", "")

      dot = run_grapher(repo)

      assert_match(/"app"\s*->\s*"models"/, dot)
    end
  end

  # ── Excluded directories ──────────────────────────────────────────────────

  def test_lib_dir_excluded
    with_repo do |repo|
      write(repo, "shard.yml", shard_yml("my_shard"))
      write(repo, "src/my_shard/core.cr", "")
      write(repo, "lib/kemal/src/kemal.cr", "")

      dot = run_grapher(repo)

      refute_match(/kemal/, dot)
    end
  end

  def test_spec_dir_excluded
    with_repo do |repo|
      write(repo, "shard.yml", shard_yml("my_shard"))
      write(repo, "src/my_shard/core.cr", "")
      write(repo, "spec/my_shard/core_spec.cr", 'require "../src/my_shard/core"')

      dot = run_grapher(repo)

      refute_match(/core_spec/, dot)
    end
  end

  # ── Deep file capping ─────────────────────────────────────────────────────

  def test_deep_files_capped_at_max_depth
    with_repo do |repo|
      write(repo, "shard.yml", shard_yml("my_shard"))
      write(repo, "src/my_shard/web/controllers/page.cr", "")
      write(repo, "src/my_shard/web/controllers/user.cr", "")

      dot = run_grapher(repo)
      # my_shard/web/controllers is depth 3; MAX_PKG_DEPTH=2 folds to my_shard/web
      refute_match(/"controllers"\s*\[/, dot)
      assert_match(/web/, dot)
    end
  end

  # ── No Crystal files ─────────────────────────────────────────────────────

  def test_no_cr_files_writes_self_marker_only
    with_repo do |repo|
      write(repo, "shard.yml", shard_yml("empty_shard"))
      write(repo, "README.md", "# hello")

      output = run_full_handler(repo)
      resources = YAML.load_stream(output)

      assert_equal(["Import"], resources.map { |r| r["kind"] })
    end
  end

  # ── Multi-shard monorepo ──────────────────────────────────────────────────

  def test_monorepo_discovers_multiple_shards
    with_repo do |repo|
      write(repo, "api/shard.yml", shard_yml("api"))
      write(repo, "api/src/api/handler.cr", "")
      write(repo, "core/shard.yml", shard_yml("core"))
      write(repo, "core/src/core/user.cr", "")

      dot = run_grapher(repo)

      assert_includes dot, "cluster"
      assert_match(/handler|user/, dot)
    end
  end

  def test_cross_shard_require_creates_edge
    with_repo do |repo|
      write(repo, "api/shard.yml", shard_yml("api"))
      # handler.cr sits directly in api/src/; ../../ reaches repo root
      write(repo, "api/src/handler.cr", "require \"../../core/src/user\"")
      write(repo, "core/shard.yml", shard_yml("core"))
      write(repo, "core/src/user.cr", "")

      dot = run_grapher(repo)
      # multi-shard has no common prefix; api/handler → api_handler, core/user → core_user
      assert_match(/"api_handler"\s*->\s*"core_user"/, dot)
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

  def shard_yml(name)
    "name: #{name}\nversion: 0.1.0\n"
  end

  def with_repo
    repo = Dir.mktmpdir
    yield repo
  ensure
    FileUtils.rm_rf(repo)
  end

  def create_handler(path:)
    annotations = { "import/handler" => "crystal-grapher" }
    annotations["import/config/path"] = path if path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:CrystalGrapher:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockCrystalImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::CrystalGrapher.new(
      import_resource,
      database: nil,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def output_path
    File.join(@resources_dir, "generated", "Import_CrystalGrapher_test.yaml")
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
    artifact&.dig("metadata", "annotations", "architecture/crystal/modules") || ""
  end

  class MockCrystalImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/crystal-grapher-test.yaml")
    end
  end
end
