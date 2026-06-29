# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/handlers/rust_grapher"
require "archsight/import/progress"

class RustGrapherTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  # ── Single crate ──────────────────────────────────────────────────────────

  def test_single_crate_generates_dot_graph
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("my_crate"))
      write(repo, "src/lib.rs", "")
      write(repo, "src/model.rs", "")

      dot = run_grapher(repo)

      assert_includes dot, "digraph"
      assert_match(/model/, dot)
    end
  end

  # ── Dependency edges ──────────────────────────────────────────────────────

  def test_dependency_edge_from_use_crate
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("my_crate"))
      write(repo, "src/lib.rs", "use crate::model::Foo;")
      write(repo, "src/model.rs", "")

      dot = run_grapher(repo)
      # Single crate: node IDs strip "my_crate/" prefix; lib.rs → root (invisible)
      # lib.rs deps are under my_crate root node; model → "model"
      assert_match(/"model"/, dot)
    end
  end

  def test_module_to_module_dependency_edge
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("my_crate"))
      write(repo, "src/lib.rs", "")
      write(repo, "src/routes.rs", "use crate::model::Foo;\nuse crate::db::Pool;")
      write(repo, "src/model.rs", "")
      write(repo, "src/db.rs", "")

      dot = run_grapher(repo)
      # node IDs strip "my_crate/" prefix
      assert_match(/"routes"\s*->\s*"model"/, dot)
      assert_match(/"routes"\s*->\s*"db"/, dot)
    end
  end

  def test_stdlib_use_produces_no_edge
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("my_crate"))
      write(repo, "src/lib.rs", "use std::collections::HashMap;\nuse core::fmt;")
      write(repo, "src/model.rs", "")

      dot = run_grapher(repo)

      refute_match(/std|core/, dot)
    end
  end

  def test_external_crate_produces_no_edge
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("my_crate"))
      write(repo, "src/lib.rs", "use tokio::runtime::Runtime;\nuse serde::Serialize;")
      write(repo, "src/model.rs", "")

      dot = run_grapher(repo)

      refute_match(/tokio|serde/, dot)
    end
  end

  # ── File mapping ──────────────────────────────────────────────────────────

  def test_lib_rs_maps_to_root_package
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("my_crate"))
      write(repo, "src/lib.rs", "use crate::model::Foo;")
      write(repo, "src/model.rs", "")

      dot = run_grapher(repo)
      # lib.rs → root; root node is invisible but model should appear
      assert_match(/model/, dot)
    end
  end

  def test_main_rs_maps_to_root_package
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("my_app"))
      write(repo, "src/main.rs", "use crate::handler::run;")
      write(repo, "src/handler.rs", "")

      dot = run_grapher(repo)

      assert_match(/handler/, dot)
    end
  end

  def test_mod_rs_maps_to_directory_module
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("my_crate"))
      write(repo, "src/lib.rs", "")
      write(repo, "src/routes/mod.rs", "use crate::model::Foo;")
      write(repo, "src/model.rs", "")

      dot = run_grapher(repo)
      # src/routes/mod.rs → my_crate/routes → node "routes"
      assert_match(/"routes"\s*->\s*"model"/, dot)
    end
  end

  # ── Deep file capping ─────────────────────────────────────────────────────

  def test_deep_files_capped_at_max_depth
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("my_crate"))
      write(repo, "src/lib.rs", "")
      write(repo, "src/web/handlers/admin.rs", "")
      write(repo, "src/web/handlers/user.rs", "")

      dot = run_grapher(repo)
      # my_crate/web/handlers is depth 3; MAX_PKG_DEPTH=2 folds to my_crate/web → "web"
      refute_match(/"handlers"/, dot)
      assert_match(/web/, dot)
    end
  end

  # ── No Rust files ─────────────────────────────────────────────────────────

  def test_no_rs_files_writes_self_marker_only
    with_repo do |repo|
      write(repo, "Cargo.toml", cargo_toml("empty_crate"))
      write(repo, "README.md", "# hello")

      output = run_full_handler(repo)
      resources = YAML.load_stream(output)

      assert_equal(["Import"], resources.map { |r| r["kind"] })
    end
  end

  # ── Cargo workspace ───────────────────────────────────────────────────────

  def test_workspace_discovers_multiple_crates
    with_repo do |repo|
      write(repo, "Cargo.toml", workspace_toml(%w[api core]))
      write(repo, "api/Cargo.toml", cargo_toml("api"))
      write(repo, "api/src/handler.rs", "")
      write(repo, "core/Cargo.toml", cargo_toml("core"))
      write(repo, "core/src/user.rs", "")

      dot = run_grapher(repo)

      assert_includes dot, "cluster"
      assert_match(/handler|user/, dot)
    end
  end

  def test_workspace_glob_pattern_expands_members
    with_repo do |repo|
      write(repo, "Cargo.toml", workspace_toml(["packages/*"]))
      write(repo, "packages/alpha/Cargo.toml", cargo_toml("alpha"))
      write(repo, "packages/alpha/src/lib.rs", "")
      write(repo, "packages/beta/Cargo.toml", cargo_toml("beta"))
      write(repo, "packages/beta/src/lib.rs", "")

      dot = run_grapher(repo)

      assert_includes dot, "cluster"
      assert_match(/alpha|beta/, dot)
    end
  end

  def test_cross_crate_use_creates_edge
    with_repo do |repo|
      write(repo, "Cargo.toml", workspace_toml(%w[api core]))
      write(repo, "api/Cargo.toml", cargo_toml("api"))
      # api crate sits directly in api/src/; cross-crate import of core
      write(repo, "api/src/lib.rs", "use core::user::User;")
      write(repo, "core/Cargo.toml", cargo_toml("core"))
      write(repo, "core/src/user.rs", "")

      dot = run_grapher(repo)
      # workspace: no common prefix; api root → "api", core/user → "core_user"
      # use core::user::User → dep core/user → node "core_user"
      assert_match(/"api"\s*->\s*"core_user"/, dot)
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

  def cargo_toml(name)
    "[package]\nname = \"#{name}\"\nversion = \"0.1.0\"\nedition = \"2021\"\n"
  end

  def workspace_toml(members)
    member_list = members.map { |m| "    \"#{m}\"" }.join(",\n")
    "[workspace]\nresolver = \"2\"\nmembers = [\n#{member_list},\n]\n"
  end

  def with_repo
    repo = Dir.mktmpdir
    yield repo
  ensure
    FileUtils.rm_rf(repo)
  end

  def create_handler(path:)
    annotations = { "import/handler" => "rust-grapher" }
    annotations["import/config/path"] = path if path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:RustGrapher:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockRustImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::RustGrapher.new(
      import_resource,
      database: nil,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def output_path
    File.join(@resources_dir, "generated", "Import_RustGrapher_test.yaml")
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
    artifact&.dig("metadata", "annotations", "architecture/rust/modules") || ""
  end

  class MockRustImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/rust-grapher-test.yaml")
    end
  end
end
