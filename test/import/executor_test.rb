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
    # Create imports with dependencies
    create_import("Import:First", handler: "test", priority: "1")
    create_import("Import:Second", handler: "test", priority: "2", depends_on: ["Import:First"])
    create_import("Import:Third", handler: "test", priority: "3", depends_on: ["Import:Second"])

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
    # Create circular dependency: A -> B -> C -> A
    create_import("Import:A", handler: "test", depends_on: ["Import:C"])
    create_import("Import:B", handler: "test", depends_on: ["Import:A"])
    create_import("Import:C", handler: "test", depends_on: ["Import:B"])

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
    create_import("Import:First", handler: "test", priority: "1")
    create_import("Import:Second", handler: "test", priority: "2", depends_on: ["Import:First"])

    db = create_database
    executor = Archsight::Import::Executor.new(database: db, resources_dir: @tmp_dir, verbose: false, output: StringIO.new)

    plan = executor.execution_plan

    assert_equal 2, plan.size
    assert_equal "Import:First", plan[0].name
    assert_equal "Import:Second", plan[1].name
  end

  private

  def create_import(name, handler:, priority: nil, depends_on: [], enabled: nil)
    annotations = { "import/handler" => handler }
    annotations["import/priority"] = priority if priority
    annotations["import/enabled"] = enabled if enabled

    spec = {}
    spec["dependsOn"] = { "imports" => depends_on } unless depends_on.empty?

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
