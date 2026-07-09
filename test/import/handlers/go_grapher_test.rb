# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/handlers/go_grapher"
require "archsight/import/progress"

class GoGrapherTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  # ── Module discovery ──────────────────────────────────────────────────────

  def test_single_root_go_mod_emits_one_component
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/myapp\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")

      resources = run_full_handler(repo)
      components = resources.select { |r| r["kind"] == "ApplicationComponent" }

      assert_equal 1, components.size
      assert_equal "example:myapp", components.first.dig("metadata", "name")
    end
  end

  def test_root_go_mod_with_subdir_go_mod_emits_two_components
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/myapp\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")
      write(repo, "pkg/go.mod", "module github.com/example/myapp/pkg\n\ngo 1.21\n")
      write(repo, "pkg/helper.go", "package pkg\n")

      resources = run_full_handler(repo)
      components = resources.select { |r| r["kind"] == "ApplicationComponent" }
      names = components.map { |c| c.dig("metadata", "name") }.sort

      assert_equal 2, components.size
      assert_includes names, "example:myapp"
      assert_includes names, "example:myapp:pkg"
    end
  end

  def test_go_work_with_multiple_modules_emits_multiple_components
    with_repo do |repo|
      write(repo, "go.work", "go 1.21\n\nuse (\n  ./service\n  ./shared\n)\n")
      write(repo, "service/go.mod", "module github.com/example/service\n\ngo 1.21\n")
      write(repo, "service/main.go", "package main\n")
      write(repo, "shared/go.mod", "module github.com/example/shared\n\ngo 1.21\n")
      write(repo, "shared/util.go", "package shared\n")

      resources = run_full_handler(repo)
      components = resources.select { |r| r["kind"] == "ApplicationComponent" }
      names = components.map { |c| c.dig("metadata", "name") }.sort

      assert_equal 2, components.size
      assert_includes names, "example:service"
      assert_includes names, "example:shared"
    end
  end

  def test_subdir_go_mods_without_root_emits_components
    with_repo do |repo|
      write(repo, "svc-a/go.mod", "module github.com/example/svc-a\n\ngo 1.21\n")
      write(repo, "svc-a/main.go", "package main\n")
      write(repo, "svc-b/go.mod", "module github.com/example/svc-b\n\ngo 1.21\n")
      write(repo, "svc-b/main.go", "package main\n")

      resources = run_full_handler(repo)
      components = resources.select { |r| r["kind"] == "ApplicationComponent" }
      names = components.map { |c| c.dig("metadata", "name") }.sort

      assert_equal 2, components.size
      assert_includes names, "example:svc-a"
      assert_includes names, "example:svc-b"
    end
  end

  def test_vendor_directory_not_scanned_for_go_mods
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/myapp\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")
      write(repo, "vendor/github.com/other/lib/go.mod", "module github.com/other/lib\n\ngo 1.21\n")

      resources = run_full_handler(repo)
      components = resources.select { |r| r["kind"] == "ApplicationComponent" }

      assert_equal 1, components.size
      assert_equal "example:myapp", components.first.dig("metadata", "name")
    end
  end

  def test_emits_go_dep_resolver_import
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/myapp\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")

      resources = run_full_handler(repo)
      imports = resources.select { |r| r["kind"] == "Import" }
      resolver = imports.find { |r| r.dig("metadata", "annotations", "import/handler") == "go-dep-resolver" }

      refute_nil resolver, "Expected a GoDepResolver Import resource in modules.yaml"
      assert_equal repo, resolver.dig("metadata", "annotations", "import/config/path")
    end
  end

  def test_components_realized_through_repo_artifact
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/myapp\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")

      resources = run_full_handler(repo)
      component = resources.find { |r| r["kind"] == "ApplicationComponent" }
      artifacts = component.dig("spec", "realizedThrough", "technologyArtifacts")

      assert_equal 1, artifacts.size
      assert_match(/\ARepo:/, artifacts.first)
    end
  end

  def test_no_go_files_writes_self_marker_only
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/empty\n\ngo 1.21\n")
      write(repo, "README.md", "# hello")

      resources = run_full_handler(repo)
      kinds = resources.map { |r| r["kind"] }

      # No Go source files → collect_packages returns empty → early return, no ApplicationComponent
      assert_equal ["Import"], kinds
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

  def with_repo
    repo = Dir.mktmpdir
    yield repo
  ensure
    FileUtils.rm_rf(repo)
  end

  def create_handler(path:)
    annotations = { "import/handler" => "go-grapher" }
    annotations["import/config/path"] = path if path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:GoGrapher:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockGoImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::GoGrapher.new(
      import_resource,
      database: nil,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def output_path
    File.join(@resources_dir, "generated", "modules.yaml")
  end

  def run_full_handler(path)
    handler = create_handler(path: path)
    handler.execute
    YAML.load_stream(File.read(output_path))
  end

  class MockGoImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/go-grapher-test.yaml")
    end
  end
end
