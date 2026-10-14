# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "archsight/import"
require "archsight/database"
require "archsight/linter"

# Handlers of the resources repository (`import/handlerPath`) and open handler names (issue #160)
class HandlerLoaderTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "imports"))
  end

  def teardown
    FileUtils.rm_rf(@dir)
    Archsight::Import::Registry.clear!
    Archsight::Import::HandlerLoader.load_builtin!
  end

  def test_loads_the_handler_an_import_declares
    name = unique_name
    write_handler("importers/example.rb", name)
    create_import("Import:Example", name, "importers/example.rb")

    assert_empty Archsight::Import::HandlerLoader.load(database)
    assert Archsight::Import::Registry[name]
  end

  def test_reports_a_path_outside_the_resources_directory_and_a_missing_file
    create_import("Import:Outside", "x", "../outside.rb")
    create_import("Import:Missing", "y", "importers/missing.rb")
    problems = Archsight::Import::HandlerLoader.load(database).map(&:to_s)

    assert(problems.any? { |p| p.include?("Import 'Import:Outside'") && p.include?("outside the resources directory") })
    assert(problems.any? { |p| p.include?("Import 'Import:Missing'") && p.include?("does not exist") })
  end

  def test_reports_a_file_that_does_not_register_the_handler
    write_handler("importers/other.rb", unique_name)
    create_import("Import:Wrong", "not-registered-#{unique_name}", "importers/other.rb")

    assert_match(/does not register the handler/, Archsight::Import::HandlerLoader.load(database).first.to_s)
  end

  def test_two_handlers_with_the_same_name_are_an_error
    name = unique_name
    write_handler("importers/first.rb", name)
    write_handler("importers/second.rb", name)
    create_import("Import:First", name, "importers/first.rb")
    create_import("Import:Second", name, "importers/second.rb")
    problems = Archsight::Import::HandlerLoader.load(database).map(&:to_s)

    assert(problems.any? { |p| p.include?("registered twice") })
  end

  def test_the_registry_rejects_a_second_class_for_a_name
    first = Class.new(Archsight::Import::Handler)
    Archsight::Import::Registry.register("dup-#{unique_name}", first)

    assert_raises(Archsight::Import::DuplicateHandlerError) do
      Archsight::Import::Registry.register("dup-#{unique_name}", Class.new(Archsight::Import::Handler))
    end
    Archsight::Import::Registry.register("dup-#{unique_name}", first) # the same class again is fine
  end

  def test_builtin_handlers_come_back_after_the_registry_was_cleared
    Archsight::Import::Registry.clear!
    Archsight::Import::HandlerLoader.load_builtin!

    assert Archsight::Import::Registry["github"]
    assert Archsight::Import::Registry["command"]
  end

  # ── Lint ─────────────────────────────────────────────────────────────────

  def test_lint_accepts_a_handler_of_the_resources_repository
    name = unique_name
    write_handler("importers/example.rb", name)
    create_import("Import:Example", name, "importers/example.rb")

    assert_empty lint_errors
  end

  def test_lint_reports_an_unknown_handler_and_a_broken_handler_file
    create_import("Import:Unknown", "no-such-handler", nil)
    FileUtils.mkdir_p(File.join(@dir, "importers"))
    File.write(File.join(@dir, "importers", "broken.rb"), "def broken(\n")
    create_import("Import:Broken", "broken", "importers/broken.rb")
    errors = lint_errors

    assert(errors.any? { |e| e.include?("unknown import handler 'no-such-handler'") })
    assert(errors.any? { |e| e.include?("Import 'Import:Broken' cannot load importers/broken.rb") })
  end

  def test_lint_reports_a_dependency_on_an_unknown_import_but_not_a_pattern
    create_import("Import:A", "command", nil, depends_on: "Import:Nope, Import:Repo:*")
    errors = lint_errors

    assert_equal(1, errors.count { |e| e.include?("depends on unknown import") })
    assert(errors.any? { |e| e.include?("'Import:Nope'") })
  end

  def test_lint_reports_a_command_that_shares_its_output_file
    create_import("Import:Teams", "command", nil, output_path: "generated/shared.yaml")
    create_import("Import:Other", "command", nil, output_path: "generated/./shared.yaml")
    create_import("Import:Own", "command", nil, output_path: "generated/own.yaml")
    errors = lint_errors.grep(/replaces its output file/)

    assert_equal 2, errors.size
    assert(errors.any? { |e| e.include?("Import 'Import:Teams'") && e.include?("'Import:Other' also writes to it") })
    refute(errors.any? { |e| e.include?("Import:Own") })
  end

  private

  def unique_name
    @unique_name ||= "local-#{object_id}-#{name.hash.abs}"
  end

  def database
    Archsight::Database.new(@dir, verbose: false, compute_annotations: false).tap(&:reload!)
  end

  def lint_errors
    Archsight::Linter.new(database).validate
  end

  def create_import(name, handler, handler_path, depends_on: nil, output_path: nil)
    annotations = { "import/handler" => handler }
    annotations["import/outputPath"] = output_path if output_path
    annotations["import/handlerPath"] = handler_path if handler_path
    annotations["import/dependsOn"] = depends_on if depends_on
    document = { "apiVersion" => "architecture/v1alpha1", "kind" => "Import",
                 "metadata" => { "name" => name, "annotations" => annotations }, "spec" => {} }
    File.write(File.join(@dir, "imports", "#{name.gsub(/\W/, "_")}.yaml"), YAML.dump(document))
  end

  def write_handler(rel_path, handler_name)
    path = File.join(@dir, rel_path)
    FileUtils.mkdir_p(File.dirname(path))
    class_name = "Loaded#{rel_path.gsub(/\W/, "_").capitalize}#{handler_name.hash.abs}"
    File.write(path, <<~RUBY)
      class #{class_name} < Archsight::Import::Handler
        def execute; end
      end
      Archsight::Import::Registry.register(#{handler_name.inspect}, #{class_name})
    RUBY
  end
end
