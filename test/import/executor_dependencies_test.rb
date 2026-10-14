# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import"
require "archsight/database"

# Declared dependencies (`import/dependsOn`), freshness that follows them, inputs, recorded outputs and required
# environment (issue #160)
class ExecutorDependenciesTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @imports_dir = File.join(@tmp_dir, "imports")
    FileUtils.mkdir_p(@imports_dir)
    Archsight::Import::Registry.clear!
    Archsight::Import::Registry.register("log", LoggingHandler)
    Archsight::Import::Registry.register("marker", MarkerHandler)
    Archsight::Import::Registry.register("generator", GeneratorHandler)
    Archsight::Import::Registry.register("pages", PagesHandler)
    LoggingHandler.log.clear
    PagesHandler.pages = %w[pages/a.md pages/b.md]
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
    Archsight::Import::Registry.clear!
  end

  # ── Order ──────────────────────────────────────────────────────────────────

  def test_a_declared_dependency_runs_first
    create_import("Import:A", handler: "log", depends_on: "Import:Z")
    create_import("Import:Z", handler: "log")
    run!

    assert_equal %w[Import:Z Import:A], LoggingHandler.log
  end

  def test_a_pattern_waits_for_the_imports_generated_in_the_same_run
    create_import("Import:Deployments", handler: "log", depends_on: "Import:Repo:*")
    create_import("Import:GitHub", handler: "generator", config: { "children" => "Import:Repo:a,Import:Repo:b" })
    run!

    assert_equal "Import:GitHub", LoggingHandler.log.first
    assert_equal "Import:Deployments", LoggingHandler.log.last
    assert_equal %w[Import:Repo:a Import:Repo:b], LoggingHandler.log[1..2].sort
  end

  def test_a_cycle_through_declared_dependencies_is_a_deadlock
    create_import("Import:A", handler: "log", depends_on: "Import:B")
    create_import("Import:B", handler: "log", depends_on: "Import:A")

    assert_raises(Archsight::Import::DeadlockError) { run! }
    assert_raises(Archsight::Import::DeadlockError) { executor.execution_plan }
  end

  def test_the_plan_shows_declared_dependencies_and_patterns_without_a_match
    create_import("Import:A", handler: "log", depends_on: "Import:Z, Import:Other:*")
    create_import("Import:Z", handler: "log")
    out = StringIO.new
    executor(output: out).execution_plan

    assert_match(/Import:A depends on: Import:Z \(Import:Other:\* matches no import yet\)/, out.string)
  end

  def test_the_filter_pulls_in_declared_dependencies
    create_import("Import:A", handler: "log", depends_on: "Import:Z")
    create_import("Import:Z", handler: "log")
    create_import("Import:Unrelated", handler: "log")
    run!(filter: "Import:A")

    assert_equal %w[Import:Z Import:A], LoggingHandler.log
  end

  # `-f X --no-deps` runs X alone, without waiting for the dependencies it does not run (no deadlock)
  def test_without_dependencies_the_filter_runs_only_the_matches
    create_import("Import:A", handler: "log", depends_on: "Import:Z, Import:Repo:*")
    create_import("Import:Z", handler: "log")
    create_import("Import:GitHub", handler: "generator", config: { "children" => "Import:Repo:a" })
    run!(filter: "\\AImport:A\\z", deps: false)

    assert_equal %w[Import:A], LoggingHandler.log

    out = StringIO.new
    plan = executor(output: out, filter: "\\AImport:A\\z", deps: false).execution_plan

    assert_equal %w[Import:A], plan.map(&:name)
    assert_includes out.string, "Dependencies: not run (--no-deps)"
  end

  # ── Freshness ──────────────────────────────────────────────────────────────

  def test_an_import_runs_again_within_its_cache_time_when_a_dependency_executed
    create_import("Import:A", handler: "marker", depends_on: "Import:Z", cache_time: "1h")
    create_import("Import:Z", handler: "log")
    run!
    LoggingHandler.log.clear
    run!

    assert_equal %w[Import:Z Import:A], LoggingHandler.log
  end

  def test_an_import_stays_cached_when_its_dependency_came_from_the_cache
    create_import("Import:A", handler: "marker", depends_on: "Import:Z", cache_time: "1h")
    create_import("Import:Z", handler: "marker", cache_time: "1h")
    run!
    LoggingHandler.log.clear
    executor = run!

    assert_empty LoggingHandler.log
    assert_empty executor.ran_imports
  end

  def test_a_changed_input_file_invalidates_the_cache
    FileUtils.mkdir_p(File.join(@tmp_dir, "data"))
    File.write(File.join(@tmp_dir, "data", "teams.txt"), "a")
    create_import("Import:A", handler: "marker", cache_time: "1h", config: { "inputs" => "data/*.txt" })
    run!
    run!

    assert_equal %w[Import:A], LoggingHandler.log

    File.write(File.join(@tmp_dir, "data", "teams.txt"), "ab")
    run!

    assert_equal %w[Import:A Import:A], LoggingHandler.log
  end

  def test_a_missing_recorded_output_invalidates_the_cache_and_an_output_not_written_again_is_deleted
    create_import("Import:Pages", handler: "pages", cache_time: "1h")
    run!
    FileUtils.rm_f(File.join(@tmp_dir, "pages", "a.md"))
    run!

    assert_equal %w[Import:Pages Import:Pages], LoggingHandler.log

    PagesHandler.pages = %w[pages/a.md]
    run!(force: true)

    assert_path_exists File.join(@tmp_dir, "pages", "a.md")
    refute_path_exists File.join(@tmp_dir, "pages", "b.md")
  end

  # ── Required environment ───────────────────────────────────────────────────

  def test_a_missing_required_variable_fails_the_import
    create_import("Import:Wiki", handler: "log", config: { "requiredEnv" => "ARCHSIGHT_TEST_UNSET_TOKEN" })

    error = assert_raises(Archsight::Import::ImportError) { run! }
    assert_includes error.message, "ARCHSIGHT_TEST_UNSET_TOKEN"
  end

  def test_an_optional_import_without_its_variable_is_skipped_and_its_dependents_run
    create_import("Import:Wiki", handler: "log", config: { "requiredEnv" => "ARCHSIGHT_TEST_UNSET_TOKEN", "optional" => "true" })
    create_import("Import:Pages", handler: "log", depends_on: "Import:Wiki")
    run!

    assert_equal %w[Import:Pages], LoggingHandler.log
  end

  # ── Handlers of the resources repository ───────────────────────────────────

  def test_an_import_runs_a_handler_from_its_handler_path
    name = "local-#{object_id}"
    write_handler("importers/example.rb", name, helper: true)
    create_import("Import:Local", handler: name, handler_path: "importers/example.rb")
    run!

    assert_equal ["Import:Local via helper"], LoggingHandler.log
  end

  def test_a_handler_file_that_does_not_load_fails_its_import
    FileUtils.mkdir_p(File.join(@tmp_dir, "importers"))
    File.write(File.join(@tmp_dir, "importers", "broken.rb"), "raise 'broken handler'\n")
    create_import("Import:Broken", handler: "broken", handler_path: "importers/broken.rb")

    error = assert_raises(Archsight::Import::ImportError) { run! }
    assert_includes error.message, "broken handler"
  end

  private

  def executor(output: StringIO.new, **)
    db = Archsight::Database.new(@tmp_dir, verbose: false, verify: true, compute_annotations: false)
    Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, output: output, **)
  end

  def run!(**)
    executor(**).tap(&:run!)
  end

  def create_import(name, handler:, depends_on: nil, handler_path: nil, cache_time: nil, config: {})
    annotations = { "import/handler" => handler }
    annotations["import/dependsOn"] = depends_on if depends_on
    annotations["import/handlerPath"] = handler_path if handler_path
    annotations["import/cacheTime"] = cache_time if cache_time
    config.each { |key, value| annotations["import/config/#{key}"] = value }
    document = { "apiVersion" => "architecture/v1alpha1", "kind" => "Import",
                 "metadata" => { "name" => name, "annotations" => annotations }, "spec" => {} }
    File.write(File.join(@imports_dir, "#{name.gsub(/[^a-zA-Z0-9]/, "_")}.yaml"), YAML.dump(document))
  end

  # A handler file of the resources repository that uses a helper next to it
  def write_handler(rel_path, name, helper: false)
    path = File.join(@tmp_dir, rel_path)
    FileUtils.mkdir_p(File.dirname(path))
    class_name = "LocalHandler#{name.gsub(/\W/, "_").capitalize}"
    File.write(File.join(File.dirname(path), "#{name}_helper.rb"), "module #{class_name}Helper; def self.suffix = ' via helper'; end\n") if helper
    File.write(path, <<~RUBY)
      #{"require_relative '#{name}_helper'" if helper}
      class #{class_name} < Archsight::Import::Handler
        def execute
          ExecutorDependenciesTest::LoggingHandler.log << (import_resource.name + #{helper ? "#{class_name}Helper.suffix" : "''"})
        end
      end
      Archsight::Import::Registry.register(#{name.inspect}, #{class_name})
    RUBY
  end

  class LoggingHandler < Archsight::Import::Handler
    @log = []
    class << self
      attr_reader :log
    end

    def execute
      LoggingHandler.log << import_resource.name
    end
  end

  # Logs and writes the self marker, so the cache applies
  class MarkerHandler < Archsight::Import::Handler
    def execute
      LoggingHandler.log << import_resource.name
      write_yaml(YAML.dump(self_marker))
    end
  end

  # Generates the child imports named in `children`, like the GitHub handler generates repository imports
  class GeneratorHandler < Archsight::Import::Handler
    def self.generates_imports? = true

    def execute
      LoggingHandler.log << import_resource.name
      children = config("children").split(",").map { |name| import_yaml(name: name, handler: "log") }
      write_yaml(resources_to_yaml(children) + YAML.dump(self_marker))
      write_generates_meta
    end
  end

  # Writes the pages in `pages` as files of its own
  class PagesHandler < Archsight::Import::Handler
    class << self
      attr_accessor :pages
    end

    def execute
      LoggingHandler.log << import_resource.name
      self.class.pages.each { |page| write_file(page, "# #{page}\n") }
      write_yaml(YAML.dump(self_marker))
    end
  end
end
