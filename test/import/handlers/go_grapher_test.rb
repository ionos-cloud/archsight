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

  def test_module_path_without_host_emits_no_component
    with_repo do |repo|
      write(repo, "go.mod", "module myapp\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")

      resources = run_full_handler(repo)

      assert_empty(resources.select { |r| r["kind"] == "ApplicationComponent" })
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

  def test_foreign_nested_go_mod_not_promoted_to_component
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/myapp\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")
      write(repo, "legacy/legacy-service/go.mod", "module github.com/other-org/legacy-service\n\ngo 1.21\n")
      write(repo, "legacy/legacy-service/main.go", "package main\n")

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

  # ── Component classification ──────────────────────────────────────────────

  def component_of(resources, name)
    resources.find { |r| r["kind"] == "ApplicationComponent" && r.dig("metadata", "name") == name }
  end

  def annotations_of(component)
    component.dig("metadata", "annotations")
  end

  def test_module_with_only_main_packages_is_an_executable
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/svc\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")
      write(repo, "internal/store/store.go", "package store\n")

      annotations = annotations_of(component_of(run_full_handler(repo), "example:svc"))

      assert_equal "executable", annotations["component/type"]
      assert_equal "ecosystem:go,packaging:go-module", annotations["architecture/tags"]
      assert_equal ".", annotations["component/entrypoints"]
    end
  end

  def test_module_without_main_packages_is_a_library
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/util\n\ngo 1.21\n")
      write(repo, "util.go", "package util\n")

      annotations = annotations_of(component_of(run_full_handler(repo), "example:util"))

      assert_equal "library", annotations["component/type"]
      assert_equal "ecosystem:go,packaging:go-module", annotations["architecture/tags"]
    end
  end

  def test_module_with_main_and_importable_packages_is_a_module
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/platform\n\ngo 1.21\n")
      write(repo, "cmd/api/main.go", "package main\n")
      write(repo, "cmd/worker/main.go", "package main\n")
      write(repo, "pkg/client/client.go", "package client\n")

      annotations = annotations_of(component_of(run_full_handler(repo), "example:platform"))

      assert_equal "module", annotations["component/type"]
      assert_equal "ecosystem:go,packaging:go-module", annotations["architecture/tags"]
      assert_equal "cmd/api,cmd/worker", annotations["component/entrypoints"]
    end
  end

  def test_tests_ignored_build_files_testdata_and_vendor_do_not_count
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/lib\n\ngo 1.21\n")
      write(repo, "lib.go", "package lib\n")
      write(repo, "lib_test.go", "package main\n")
      write(repo, "gen.go", "//go:build ignore\n\npackage main\n")
      write(repo, "testdata/main.go", "package main\n")
      write(repo, "vendor/x/main.go", "package main\n")

      annotations = annotations_of(component_of(run_full_handler(repo), "example:lib"))

      assert_equal "library", annotations["component/type"]
    end
  end

  def test_nested_module_is_classified_on_its_own
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/myapp\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")
      write(repo, "pkg/go.mod", "module github.com/example/myapp/pkg\n\ngo 1.21\n")
      write(repo, "pkg/helper.go", "package pkg\n")

      resources = run_full_handler(repo)

      assert_equal "executable", annotations_of(component_of(resources, "example:myapp"))["component/type"]
      assert_equal "library", annotations_of(component_of(resources, "example:myapp:pkg"))["component/type"]
    end
  end

  def test_entrypoints_are_limited_and_generated_annotations_are_kept
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/many\n\ngo 1.21\n")
      12.times { |i| write(repo, "cmd/c#{format("%02d", i)}/main.go", "package main\n") }

      annotations = annotations_of(component_of(run_full_handler(repo), "example:many"))

      assert_equal 10, annotations["component/entrypoints"].split(",").size
      refute_includes annotations["architecture/tags"], "entrypoint:"
      assert annotations.key?("generated/script")
    end
  end

  def test_a_component_type_from_another_source_is_not_overwritten
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/svc\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")
      curated = { "example:svc" => { "component/type" => "plugin" } }

      handler = create_handler(path: repo, database: MockDatabase.new(curated))
      handler.execute
      annotations = annotations_of(component_of(YAML.load_stream(File.read(output_path)), "example:svc"))

      refute annotations.key?("component/type")
      refute annotations.key?("architecture/tags")
    end
  end

  def test_tags_a_person_set_stay_and_machine_tags_are_added
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/svc\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")
      existing = { "example:svc" => { "architecture/tags" => "billing, payments" } }

      handler = create_handler(path: repo, database: MockDatabase.new(existing))
      handler.execute
      annotations = annotations_of(component_of(YAML.load_stream(File.read(output_path)), "example:svc"))

      assert_equal "billing,payments,ecosystem:go,packaging:go-module", annotations["architecture/tags"]
    end
  end

  def test_machine_tags_of_an_earlier_run_are_replaced_and_old_entrypoint_tags_removed
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/svc\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")
      earlier = { "architecture/tags" => "billing,ecosystem:go,entrypoint:cmd/old,team:red",
                  "generated/script" => "Import:GoGrapher:test" }

      handler = create_handler(path: repo, database: MockDatabase.new("example:svc" => earlier))
      handler.execute
      annotations = annotations_of(component_of(YAML.load_stream(File.read(output_path)), "example:svc"))

      assert_equal "billing,team:red,ecosystem:go,packaging:go-module", annotations["architecture/tags"]
      assert_equal ".", annotations["component/entrypoints"]
    end
  end

  def test_own_earlier_output_is_regenerated
    with_repo do |repo|
      write(repo, "go.mod", "module github.com/example/svc\n\ngo 1.21\n")
      write(repo, "main.go", "package main\n")
      earlier = { "example:svc" => { "component/type" => "library", "generated/script" => "Import:GoGrapher:test" } }

      handler = create_handler(path: repo, database: MockDatabase.new(earlier))
      handler.execute
      annotations = annotations_of(component_of(YAML.load_stream(File.read(output_path)), "example:svc"))

      assert_equal "executable", annotations["component/type"]
    end
  end

  # ── Two repositories with the same module path (issue #150) ──────────────

  SHOP = "alice:shop"
  GENERATED = { "generated/script" => "Import:GoGrapher:other" }.freeze

  # A repository checked out from acme/<name>, declaring the module github.com/alice/shop
  def shop_repo(repo, name)
    write(repo, ".git/config", "[remote \"origin\"]\n\turl = git@github.com:acme/#{name}.git\n")
    write(repo, "go.mod", "module github.com/alice/shop\n\ngo 1.21\n")
    write(repo, "main.go", "package main\n")
  end

  # The database after both repositories were imported once: one merged component realized by both
  def merged_shop(artifacts = {})
    MockDatabase.new({ SHOP => GENERATED },
                     { specs: { SHOP => { "realizedThrough" => { "technologyArtifacts" => %w[Repo:acme:shop Repo:acme:shop-prototype] } } },
                       artifacts: artifacts })
  end

  def component_names_for(repo, database)
    create_handler(path: repo, database: database).execute
    YAML.load_stream(File.read(output_path)).select { |r| r["kind"] == "ApplicationComponent" }.map { |r| r.dig("metadata", "name") }
  end

  def test_an_archived_repository_with_the_same_module_path_gets_a_suffixed_name
    archived = { "Repo:acme:shop-prototype" => { "activity/status" => "archived" }, "Repo:acme:shop" => { "activity/status" => "active" } }
    with_repo do |repo|
      shop_repo(repo, "shop-prototype")

      assert_equal ["alice:shop@acme:shop-prototype"], component_names_for(repo, merged_shop(archived))
    end
    with_repo do |repo|
      shop_repo(repo, "shop")

      assert_equal [SHOP], component_names_for(repo, merged_shop(archived))
    end
  end

  def test_the_non_archived_repository_keeps_the_name_even_when_it_sorts_last
    archived = { "Repo:acme:shop" => { "activity/status" => "archived" } }
    with_repo do |repo|
      shop_repo(repo, "shop-prototype")

      assert_equal [SHOP], component_names_for(repo, merged_shop(archived))
    end
  end

  def test_without_an_archived_repository_the_first_by_name_keeps_the_name
    with_repo do |repo|
      shop_repo(repo, "shop")

      assert_equal [SHOP], component_names_for(repo, merged_shop)
    end
    with_repo do |repo|
      shop_repo(repo, "shop-prototype")

      assert_equal ["alice:shop@acme:shop-prototype"], component_names_for(repo, merged_shop)
    end
  end

  def test_a_component_only_this_repository_realizes_keeps_its_name
    with_repo do |repo|
      shop_repo(repo, "shop-prototype")
      own = MockDatabase.new({ SHOP => GENERATED }, { specs: { SHOP => { "realizedThrough" => { "technologyArtifacts" => %w[Repo:acme:shop-prototype] } } } })

      assert_equal [SHOP], component_names_for(repo, own)
    end
  end

  def test_a_curated_component_listing_several_repositories_is_not_split
    with_repo do |repo|
      shop_repo(repo, "shop-prototype")
      curated = MockDatabase.new({ SHOP => { "component/type" => "module" } },
                                 { specs: { SHOP => { "realizedThrough" => { "technologyArtifacts" => %w[Repo:acme:shop Repo:acme:shop-prototype] } } } })

      assert_equal [SHOP], component_names_for(repo, curated)
    end
  end

  # ── A copy of another repository's module (issue #157) ───────────────────

  LIBRARY = "acme:library"

  # acme/library declares github.com/acme/library; acme/app-poc embeds a copy of it in a subdirectory
  def library_repo(repo, name, copy_dir: nil)
    write(repo, ".git/config", "[remote \"origin\"]\n\turl = git@github.com:acme/#{name}.git\n")
    dir = copy_dir ? "#{copy_dir}/" : ""
    write(repo, "#{dir}go.mod", "module github.com/acme/library\n\ngo 1.21\n")
    write(repo, "#{dir}library.go", "package library\n")
  end

  def merged_library(realized_by, artifacts = { "Repo:acme:library" => {}, "Repo:acme:app-poc" => {} })
    MockDatabase.new({ LIBRARY => GENERATED },
                     { specs: { LIBRARY => { "realizedThrough" => { "technologyArtifacts" => realized_by } } }, artifacts: artifacts })
  end

  def test_the_repository_the_module_path_names_keeps_the_name_although_it_sorts_last
    with_repo do |repo|
      library_repo(repo, "library")

      assert_equal [LIBRARY], component_names_for(repo, merged_library(%w[Repo:acme:app-poc Repo:acme:library]))
    end
    with_repo do |repo|
      library_repo(repo, "app-poc")

      assert_equal ["acme:library@acme:app-poc"], component_names_for(repo, merged_library(%w[Repo:acme:app-poc Repo:acme:library]))
    end
  end

  def test_the_module_path_wins_over_the_archived_state
    archived = { "Repo:acme:library" => { "activity/status" => "archived" }, "Repo:acme:app-poc" => {} }
    with_repo do |repo|
      library_repo(repo, "app-poc")

      assert_equal ["acme:library@acme:app-poc"], component_names_for(repo, merged_library(%w[Repo:acme:app-poc Repo:acme:library], archived))
    end
  end

  def test_a_nested_copy_of_another_repositorys_module_gets_no_component
    with_repo do |repo|
      library_repo(repo, "app-poc", copy_dir: "third_party/library")
      # the copy owned the plain name before; importing only this repository again gives it up
      output = run_full_handler(repo, database: merged_library(%w[Repo:acme:app-poc]))

      assert_empty(output.select { |r| r["kind"] == "ApplicationComponent" })
    end
  end

  def test_a_nested_module_is_kept_while_its_repository_is_unknown
    with_repo do |repo|
      library_repo(repo, "app-poc", copy_dir: "third_party/library")

      assert_equal [LIBRARY], component_names_for(repo, MockDatabase.new({}, { artifacts: { "Repo:acme:app-poc" => {} } }))
    end
  end

  def test_the_module_path_names_a_repository
    parser = Object.new.extend(Archsight::Import::Handlers::GoModuleParser)

    assert parser.module_path_of_repository?("github.com/acme/library", "Repo:acme:library")
    assert parser.module_path_of_repository?("github.com/acme/library/v2/client", "Repo:acme:library")
    assert parser.module_path_of_repository?("github.com/acme/library", "Repo:library")
    assert parser.module_path_of_repository?("go.example.com/library", "Repo:acme:library")
    refute parser.module_path_of_repository?("github.com/acme/library", "Repo:acme:app-poc")
    refute parser.module_path_of_repository?("github.com/alice/shop", "Repo:acme:shop")
    refute parser.module_path_of_repository?("github.com/acme/library", "Repo:acme")
  end

  def test_the_dependency_resolver_import_knows_the_artifact
    with_repo do |repo|
      shop_repo(repo, "shop")
      resolver = run_full_handler(repo).find { |r| r["kind"] == "Import" }

      assert_equal "Repo:acme:shop", resolver.dig("metadata", "annotations", "import/config/artifact")
    end
  end

  # ── Error cases ───────────────────────────────────────────────────────────

  def test_missing_path_raises_error
    handler = create_handler(path: nil)
    assert_raises(RuntimeError) { handler.execute }
  end

  def test_nonexistent_path_is_skipped
    handler = create_handler(path: "/nonexistent/path/does/not/exist")
    handler.execute # repository not cloned (yet): warns and writes nothing
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

  def create_handler(path:, database: nil)
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
      database: database,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def output_path
    File.join(@resources_dir, "generated", "modules.yaml")
  end

  def run_full_handler(path, database: nil)
    handler = create_handler(path: path, database: database)
    handler.execute
    YAML.load_stream(File.read(output_path))
  end

  # Minimal database stub: ApplicationComponents keyed by name, with the given annotations
  class MockDatabase
    Component = Struct.new(:annotations, :raw)

    # annotations_by_name: ApplicationComponents; specs: their spec; artifacts: TechnologyArtifact annotations
    # (positional so that a component named like "example:svc" is not taken for a keyword)
    def initialize(annotations_by_name, extra = {})
      specs = extra.fetch(:specs, {})
      @instances = annotations_by_name.to_h { |name, annotations| [name, Component.new(annotations, { "spec" => specs.fetch(name, {}) })] }
      @artifacts = extra.fetch(:artifacts, {}).transform_values { |annotations| Component.new(annotations, {}) }
    end

    def instances_by_kind(kind)
      { "ApplicationComponent" => @instances, "TechnologyArtifact" => @artifacts }.fetch(kind, {})
    end
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
