# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/handlers/elixir_grapher"
require "archsight/import/progress"

class ElixirGrapherTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  # ── Single app ────────────────────────────────────────────────────────────

  def test_single_app_generates_dot_graph
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/accounts.ex", "defmodule MyApp.Accounts do\nend\n")
      write(repo, "lib/my_app/user.ex", "defmodule MyApp.User do\nend\n")

      dot = run_grapher(repo)
      assert_includes dot, "digraph"
      assert_match(/accounts|user/, dot)
    end
  end

  def test_dependency_edge_from_alias
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/web/router.ex",
            "defmodule MyApp.Web.Router do\n  alias MyApp.Accounts\nend\n")
      write(repo, "lib/my_app/accounts.ex", "defmodule MyApp.Accounts do\nend\n")

      dot = run_grapher(repo)
      # node IDs strip common "my_app/" prefix; "/" → "_": web/router → web_router, accounts → accounts
      assert_match(/"web_router"\s*->\s*"accounts"/, dot)
    end
  end

  def test_dependency_edge_from_import
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/web/router.ex",
            "defmodule MyApp.Web.Router do\n  import MyApp.Helpers\nend\n")
      write(repo, "lib/my_app/helpers.ex", "defmodule MyApp.Helpers do\nend\n")

      dot = run_grapher(repo)
      assert_match(/"web_router"\s*->\s*"helpers"/, dot)
    end
  end

  def test_dependency_edge_from_use
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/web/controller.ex",
            "defmodule MyApp.Web.Controller do\n  use MyApp.Accounts\nend\n")
      write(repo, "lib/my_app/accounts.ex", "defmodule MyApp.Accounts do\nend\n")

      dot = run_grapher(repo)
      assert_match(/"web_controller"\s*->\s*"accounts"/, dot)
    end
  end

  def test_multi_alias_expands_to_multiple_edges
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/api/handler.ex",
            "defmodule MyApp.Api.Handler do\n  alias MyApp.{Accounts, Repo}\nend\n")
      write(repo, "lib/my_app/accounts.ex", "defmodule MyApp.Accounts do\nend\n")
      write(repo, "lib/my_app/repo.ex", "defmodule MyApp.Repo do\nend\n")

      dot = run_grapher(repo)
      assert_match(/"api_handler"\s*->\s*"accounts"/, dot)
      assert_match(/"api_handler"\s*->\s*"repo"/, dot)
    end
  end

  # ── External deps filtered ────────────────────────────────────────────────

  def test_external_deps_produce_no_edges
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/schema.ex",
            "defmodule MyApp.Schema do\n  use Ecto.Schema\n  import Phoenix.Controller\nend\n")

      dot = run_grapher(repo)
      refute_match(/Ecto/, dot)
      refute_match(/Phoenix/, dot)
    end
  end

  # ── Excluded directories ──────────────────────────────────────────────────

  def test_build_dir_excluded
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/core.ex", "defmodule MyApp.Core do\nend\n")
      write(repo, "_build/dev/lib/my_app/compiled.ex", "defmodule MyApp.Compiled do\nend\n")

      dot = run_grapher(repo)
      refute_match(/compiled/, dot)
    end
  end

  def test_deps_dir_excluded
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/core.ex", "defmodule MyApp.Core do\nend\n")
      write(repo, "deps/ecto/lib/ecto/schema.ex", "defmodule Ecto.Schema do\nend\n")

      dot = run_grapher(repo)
      refute_includes dot, "ecto"
    end
  end

  def test_test_dir_excluded
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/service.ex", "defmodule MyApp.Service do\nend\n")
      write(repo, "test/my_app/service_test.exs",
            "defmodule MyApp.ServiceTest do\n  alias MyApp.Service\nend\n")

      dot = run_grapher(repo)
      refute_match(/service_test/, dot)
    end
  end

  # ── Deep file capping ─────────────────────────────────────────────────────

  def test_deep_files_capped_at_max_depth
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/web/controllers/page_controller.ex",
            "defmodule MyApp.Web.Controllers.PageController do\nend\n")
      write(repo, "lib/my_app/web/controllers/user_controller.ex",
            "defmodule MyApp.Web.Controllers.UserController do\nend\n")

      dot = run_grapher(repo)
      # Depth-3 package my_app/web/controllers should remain (MAX_PKG_DEPTH=3)
      assert_match(/web\/controllers|controllers/, dot)
      # But depth-4 (my_app/web/controllers/sub) would fold — just checking depth 3 stays
    end
  end

  def test_depth_4_folded_to_depth_3
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("my_app"))
      write(repo, "lib/my_app/web/controllers/admin/dashboard.ex",
            "defmodule MyApp.Web.Controllers.Admin.Dashboard do\nend\n")

      dot = run_grapher(repo)
      # depth-4 package my_app/web/controllers/admin folds to my_app/web/controllers
      # node ID strips "my_app/" prefix, "/" → "_": web_controllers
      refute_match(/"web_controllers_admin"/, dot)
      assert_match(/web_controllers/, dot)
    end
  end

  # ── Umbrella project ──────────────────────────────────────────────────────

  def test_umbrella_discovers_multiple_apps
    with_repo do |repo|
      write(repo, "mix.exs", umbrella_mixexs)
      write(repo, "apps/api/mix.exs", mixexs("api"))
      write(repo, "apps/api/lib/api/router.ex", "defmodule Api.Router do\nend\n")
      write(repo, "apps/core/mix.exs", mixexs("core"))
      write(repo, "apps/core/lib/core/user.ex", "defmodule Core.User do\nend\n")

      dot = run_grapher(repo)
      assert_includes dot, "digraph"
      assert_includes dot, "cluster"
      assert_match(/router|user/, dot)
    end
  end

  def test_umbrella_cross_app_import_creates_edge
    with_repo do |repo|
      write(repo, "mix.exs", umbrella_mixexs)
      write(repo, "apps/api/mix.exs", mixexs("api"))
      write(repo, "apps/api/lib/api/handler.ex",
            "defmodule Api.Handler do\n  alias Core.User\nend\n")
      write(repo, "apps/core/mix.exs", mixexs("core"))
      write(repo, "apps/core/lib/core/user.ex", "defmodule Core.User do\nend\n")

      dot = run_grapher(repo)
      # umbrella has no common prefix; api/handler → api_handler, core/user → core_user
      assert_match(/"api_handler"\s*->\s*"core_user"/, dot)
    end
  end

  # ── No Elixir files ───────────────────────────────────────────────────────

  def test_no_ex_files_writes_self_marker_only
    with_repo do |repo|
      write(repo, "mix.exs", mixexs("empty_app"))
      write(repo, "README.md", "# hello")

      output = run_full_handler(repo)
      resources = YAML.load_stream(output)
      assert_equal ["Import"], resources.map { |r| r["kind"] }
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

  def mixexs(app_name)
    <<~ELIXIR
      defmodule #{camelize(app_name)}.MixProject do
        use Mix.Project
        def project do
          [app: :#{app_name}, version: "0.1.0"]
        end
      end
    ELIXIR
  end

  def umbrella_mixexs
    <<~ELIXIR
      defmodule Umbrella.MixProject do
        use Mix.Project
        def project do
          [apps_path: "apps", version: "0.1.0"]
        end
      end
    ELIXIR
  end

  def camelize(str)
    str.split("_").map(&:capitalize).join
  end

  def with_repo
    repo = Dir.mktmpdir
    yield repo
  ensure
    FileUtils.rm_rf(repo)
  end

  def create_handler(path:)
    annotations = { "import/handler" => "elixir-grapher" }
    annotations["import/config/path"] = path if path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:ElixirGrapher:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockElixirImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::ElixirGrapher.new(
      import_resource,
      database: nil,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def output_path
    File.join(@resources_dir, "generated", "Import_ElixirGrapher_test.yaml")
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
    artifact&.dig("metadata", "annotations", "architecture/elixir/modules") || ""
  end

  class MockElixirImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/elixir-grapher-test.yaml")
    end
  end
end
