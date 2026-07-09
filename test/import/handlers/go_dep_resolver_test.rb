# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/handlers/go_dep_resolver"
require "archsight/import/progress"

class GoDepResolverTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  # ── Core dependency resolution ────────────────────────────────────────────

  def test_emits_component_with_dep_when_target_exists_in_database
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/app\n\ngo 1.21\n\nrequire github.com/example/lib v1.0.0\n")

      # Both the component itself and its dep must be in the database (as they would
      # be after GoGrapher's iteration-1 run seeded them).
      db = mock_database("example:app" => {}, "example:lib" => {})
      handler = create_handler(path: repo, database: db)
      handler.execute

      resources = YAML.load_stream(File.read(output_path))
      components = resources.select { |r| r["kind"] == "ApplicationComponent" }

      assert_equal 1, components.size
      assert_equal "example:app", components.first.dig("metadata", "name")
      assert_equal ["example:lib"], components.first.dig("spec", "dependsOn", "applicationComponents")
    end
  end

  def test_skips_dep_when_target_not_in_database
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/app\n\ngo 1.21\n\nrequire github.com/example/lib v1.0.0\n")

      # The dep (example:lib) is absent from the database → no component emitted
      db = mock_database("example:app" => {})
      handler = create_handler(path: repo, database: db)
      handler.execute

      resources = YAML.load_stream(File.read(output_path))
      components = resources.select { |r| r["kind"] == "ApplicationComponent" }

      assert_empty components
    end
  end

  def test_skips_module_with_no_same_origin_deps
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/app\n\ngo 1.21\n\nrequire github.com/other-org/lib v1.0.0\n")

      # other-org is a different origin prefix → filtered out regardless of DB state
      db = mock_database("example:app" => {}, "other-org:lib" => {})
      handler = create_handler(path: repo, database: db)
      handler.execute

      resources = YAML.load_stream(File.read(output_path))
      components = resources.select { |r| r["kind"] == "ApplicationComponent" }

      assert_empty components
    end
  end

  def test_preserves_existing_spec_fields_when_adding_dep
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/app\n\ngo 1.21\n\nrequire github.com/example/lib v1.0.0\n")

      existing_spec = { "realizedThrough" => { "technologyArtifacts" => ["Repo:example:app"] },
                        "exposes" => { "applicationInterfaces" => ["Private:App:v1:RestAPI"] } }
      db = mock_database("example:lib" => {}, "example:app" => existing_spec)
      handler = create_handler(path: repo, database: db)
      handler.execute

      resources = YAML.load_stream(File.read(output_path))
      component = resources.find { |r| r["kind"] == "ApplicationComponent" }

      assert_equal ["Repo:example:app"], component.dig("spec", "realizedThrough", "technologyArtifacts")
      assert_equal ["Private:App:v1:RestAPI"], component.dig("spec", "exposes", "applicationInterfaces")
      assert_equal ["example:lib"], component.dig("spec", "dependsOn", "applicationComponents")
    end
  end

  def test_handles_multi_module_repo
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/app\n\ngo 1.21\n\nrequire github.com/example/shared v1.0.0\n")
      write(repo, "worker/go.mod", "module github.com/example/app/worker\n\ngo 1.21\n\nrequire github.com/example/shared v1.0.0\n")

      db = mock_database("example:shared" => {}, "example:app" => {}, "example:app:worker" => {})
      handler = create_handler(path: repo, database: db)
      handler.execute

      resources = YAML.load_stream(File.read(output_path))
      components = resources.select { |r| r["kind"] == "ApplicationComponent" }
      names = components.map { |c| c.dig("metadata", "name") }.sort

      assert_equal %w[example:app example:app:worker], names
      components.each do |c|
        assert_equal ["example:shared"], c.dig("spec", "dependsOn", "applicationComponents")
      end
    end
  end

  def test_writes_only_self_marker_when_no_deps
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/app\n\ngo 1.21\n")

      db = mock_database({})
      handler = create_handler(path: repo, database: db)
      handler.execute

      resources = YAML.load_stream(File.read(output_path))

      kinds = resources.map { |r| r["kind"] }

      assert_equal ["Import"], kinds
    end
  end

  def test_dep_names_are_sorted
    with_repo do |repo|
      write(repo, "go.mod", <<~GOMOD)
        module github.com/example/app

        go 1.21

        require (
          github.com/example/zebra v1.0.0
          github.com/example/alpha v1.0.0
          github.com/example/middle v1.0.0
        )
      GOMOD

      db = mock_database("example:app" => {}, "example:zebra" => {}, "example:alpha" => {}, "example:middle" => {})
      handler = create_handler(path: repo, database: db)
      handler.execute

      resources = YAML.load_stream(File.read(output_path))
      component = resources.find { |r| r["kind"] == "ApplicationComponent" }

      assert_equal %w[example:alpha example:middle example:zebra],
                   component.dig("spec", "dependsOn", "applicationComponents")
    end
  end

  # ── Error cases ───────────────────────────────────────────────────────────

  def test_missing_path_raises_error
    handler = create_handler(path: nil)
    assert_raises(RuntimeError) { handler.execute }
  end

  def test_nonexistent_path_raises_error
    handler = create_handler(path: "/nonexistent/does/not/exist")
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

  def output_path
    File.join(@resources_dir, "generated", "relationships.yaml")
  end

  def create_handler(path:, database: nil)
    annotations = { "import/handler" => "go-dep-resolver" }
    annotations["import/config/path"] = path if path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:GoDepResolver:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockGoDepResolverImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::GoDepResolver.new(
      import_resource,
      database: database,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  # Minimal database stub that returns ApplicationComponent instances keyed by name.
  def mock_database(components_by_name)
    instances = components_by_name.transform_values { |spec| MockComponent.new(spec) }
    MockDatabase.new(instances)
  end

  class MockDatabase
    def initialize(instances)
      @instances = instances
    end

    def instances_by_kind(kind)
      kind == "ApplicationComponent" ? @instances : {}
    end
  end

  class MockComponent
    attr_reader :annotations

    def initialize(spec)
      @spec = spec
      @annotations = {}
    end

    def raw
      { "spec" => @spec }
    end
  end

  class MockGoDepResolverImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/go-dep-resolver-test.yaml")
    end
  end
end
