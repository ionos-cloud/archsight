# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/executor"
require "archsight/import/registry"
require "archsight/import/handler"
require "archsight/database"

class ExecutorTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir
    @imports_dir = File.join(@tmp_dir, "imports")

    FileUtils.mkdir_p(@imports_dir)

    # Register test handler
    Archsight::Import::Registry.clear!
    Archsight::Import::Registry.register("test", TestExecutionHandler)
    TestExecutionHandler.reset_execution_log
  end

  def teardown
    FileUtils.rm_rf(@tmp_dir)
    Archsight::Import::Registry.clear!
  end

  def test_runs_single_import
    create_import("Import:Test", handler: "test")

    db = create_database
    executor = Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, verbose: false, output: StringIO.new)
    executor.run!

    assert_includes TestExecutionHandler.execution_log, "Import:Test"
  end

  def test_runs_imports_in_dependency_order
    # Create imports with dependencies via generates relation
    # Import:First generates Import:Second, so Second depends on First
    # Import:Second generates Import:Third, so Third depends on Second
    create_import("Import:First", handler: "test", priority: "1", generates: ["Import:Second"])
    create_import("Import:Second", handler: "test", priority: "2", generates: ["Import:Third"])
    create_import("Import:Third", handler: "test", priority: "3")

    db = create_database
    executor = Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, verbose: false, output: StringIO.new)
    executor.run!

    log = TestExecutionHandler.execution_log

    assert_equal 3, log.size

    # Verify order
    first_idx = log.index("Import:First")
    second_idx = log.index("Import:Second")
    third_idx = log.index("Import:Third")

    assert_operator first_idx, :<, second_idx, "First should run before Second"
    assert_operator second_idx, :<, third_idx, "Second should run before Third"
  end

  def test_skips_disabled_imports
    create_import("Import:Enabled", handler: "test")
    create_import("Import:Disabled", handler: "test", enabled: "false")

    db = create_database
    executor = Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, verbose: false, output: StringIO.new)
    executor.run!

    log = TestExecutionHandler.execution_log

    assert_includes log, "Import:Enabled"
    refute_includes log, "Import:Disabled"
  end

  def test_respects_priority
    create_import("Import:Low", handler: "test", priority: "100")
    create_import("Import:High", handler: "test", priority: "1")
    create_import("Import:Medium", handler: "test", priority: "50")

    db = create_database
    executor = Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, verbose: false, output: StringIO.new)
    executor.run!

    log = TestExecutionHandler.execution_log
    high_idx = log.index("Import:High")
    medium_idx = log.index("Import:Medium")
    low_idx = log.index("Import:Low")

    assert_operator high_idx, :<, medium_idx, "High priority should run before medium"
    assert_operator medium_idx, :<, low_idx, "Medium priority should run before low"
  end

  def test_detects_circular_dependency
    # Create circular dependency via generates: C generates A, A generates B, B generates C
    # This means: A depends on C, B depends on A, C depends on B (circular)
    create_import("Import:A", handler: "test", generates: ["Import:B"])
    create_import("Import:B", handler: "test", generates: ["Import:C"])
    create_import("Import:C", handler: "test", generates: ["Import:A"])

    db = create_database
    executor = Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, verbose: false, output: StringIO.new)

    assert_raises(Archsight::Import::DeadlockError) do
      executor.run!
    end
  end

  def test_fails_on_handler_error
    Archsight::Import::Registry.register("failing", FailingHandler)
    create_import("Import:Failing", handler: "failing")

    db = create_database
    executor = Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, verbose: false, output: StringIO.new)

    assert_raises(Archsight::Import::ImportError) do
      executor.run!
    end
  end

  def test_execution_plan_returns_sorted_imports
    # Import:First generates Import:Second, so Second depends on First
    create_import("Import:First", handler: "test", priority: "1", generates: ["Import:Second"])
    create_import("Import:Second", handler: "test", priority: "2")

    db = create_database
    executor = Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, verbose: false, output: StringIO.new)

    plan = executor.execution_plan

    assert_equal 2, plan.size
    assert_equal "Import:First", plan[0].name
    assert_equal "Import:Second", plan[1].name
  end

  def test_filter_runs_only_matching_imports
    create_import("Import:RestApi:dns", handler: "test")
    create_import("Import:RestApi:compute", handler: "test")
    create_import("Import:GitHub:repo", handler: "test")

    db = create_database
    executor = Archsight::Import::Executor.new(
      database: db,
      resources_dir: @tmp_dir,
      verbose: false,
      output: StringIO.new,
      filter: "RestApi"
    )
    executor.run!

    log = TestExecutionHandler.execution_log

    assert_includes log, "Import:RestApi:dns"
    assert_includes log, "Import:RestApi:compute"
    refute_includes log, "Import:GitHub:repo"
  end

  def test_filter_with_regex_pattern
    create_import("Import:RestApi:public:dns:v1", handler: "test")
    create_import("Import:RestApi:private:dns:v1", handler: "test")
    create_import("Import:RestApi:public:compute:v1", handler: "test")

    db = create_database
    executor = Archsight::Import::Executor.new(
      database: db,
      resources_dir: @tmp_dir,
      verbose: false,
      output: StringIO.new,
      filter: "public.*dns"
    )
    executor.run!

    log = TestExecutionHandler.execution_log

    assert_includes log, "Import:RestApi:public:dns:v1"
    refute_includes log, "Import:RestApi:private:dns:v1"
    refute_includes log, "Import:RestApi:public:compute:v1"
  end

  def test_execution_plan_respects_filter
    create_import("Import:RestApi:dns", handler: "test")
    create_import("Import:GitHub:repo", handler: "test")

    db = create_database
    output = StringIO.new
    executor = Archsight::Import::Executor.new(
      database: db,
      resources_dir: @tmp_dir,
      verbose: false,
      output: output,
      filter: "RestApi"
    )

    plan = executor.execution_plan

    assert_equal 1, plan.size
    assert_equal "Import:RestApi:dns", plan[0].name
  end

  def test_filter_includes_dependencies_of_matching_imports
    # Index doesn't match filter but generates the imports that do match (so it's a dependency)
    create_import("Import:GitHub:Index", handler: "test", priority: "1",
                                         generates: %w[Import:Repo:rest-api-one Import:Repo:rest-api-two])
    # These match the filter and depend on Index (via generates)
    create_import("Import:Repo:rest-api-one", handler: "test", priority: "2")
    create_import("Import:Repo:rest-api-two", handler: "test", priority: "2")
    # This doesn't match and isn't a dependency
    create_import("Import:Other:unrelated", handler: "test")

    db = create_database
    executor = Archsight::Import::Executor.new(
      database: db,
      resources_dir: @tmp_dir,
      verbose: false,
      output: StringIO.new,
      filter: "rest-api"
    )
    executor.run!

    log = TestExecutionHandler.execution_log

    # Should include the dependency even though it doesn't match the filter
    assert_includes log, "Import:GitHub:Index"
    assert_includes log, "Import:Repo:rest-api-one"
    assert_includes log, "Import:Repo:rest-api-two"
    # Should not include unrelated import
    refute_includes log, "Import:Other:unrelated"
  end

  def test_rejects_import_with_depends_on_spec
    # Create an Import with the old dependsOn spec (no longer supported)
    yaml_content = YAML.dump({
                               "apiVersion" => "architecture/v1alpha1",
                               "kind" => "Import",
                               "metadata" => {
                                 "name" => "Import:WithDependsOn",
                                 "annotations" => { "import/handler" => "test" }
                               },
                               "spec" => {
                                 "dependsOn" => { "imports" => ["Import:Parent"] }
                               }
                             })
    File.write(File.join(@imports_dir, "import_with_depends_on.yaml"), yaml_content)

    db = create_database
    executor = Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, verbose: false, output: StringIO.new)

    # Database should reject this during reload (triggered by executor.run!)
    error = assert_raises(Archsight::ResourceError) do
      executor.run!
    end

    assert_includes error.message, "unknown verb dependsOn"
  end

  private

  def create_import(name, handler:, priority: nil, generates: [], enabled: nil)
    annotations = { "import/handler" => handler }
    annotations["import/priority"] = priority if priority
    annotations["import/enabled"] = enabled if enabled

    spec = {}
    spec["generates"] = { "imports" => generates } unless generates.empty?

    yaml_content = YAML.dump({
                               "apiVersion" => "architecture/v1alpha1",
                               "kind" => "Import",
                               "metadata" => {
                                 "name" => name,
                                 "annotations" => annotations
                               },
                               "spec" => spec
                             })

    filename = "#{name.gsub(/[^a-zA-Z0-9]/, "_")}.yaml"
    File.write(File.join(@imports_dir, filename), yaml_content)
  end

  def create_database
    # Create a minimal database that loads from our test directories
    Archsight::Database.new(@tmp_dir, verbose: false, verify: true, compute_annotations: false)
  end

  # Test handler that logs executions
  class TestExecutionHandler < Archsight::Import::Handler
    @execution_log = []

    class << self
      attr_accessor :execution_log

      def reset_execution_log
        @execution_log = []
      end
    end

    def execute
      self.class.execution_log << import_resource.name
    end
  end

  # Handler that always fails
  class FailingHandler < Archsight::Import::Handler
    def execute
      raise "Intentional failure for testing"
    end
  end
end
