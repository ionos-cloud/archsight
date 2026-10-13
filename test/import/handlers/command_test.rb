# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import"
require "archsight/database"

# `import/handler: command` runs a program of the resources repository as an import (issue #160)
class CommandHandlerTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "imports"))
    Archsight::Import::HandlerLoader.load_builtin!
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_the_resources_the_program_writes_are_marked_and_the_marker_is_added
    write_script(<<~SH)
      cat > "$ARCHSIGHT_OUTPUT_PATH" <<YAML
      apiVersion: architecture/v1alpha1
      kind: BusinessActor
      metadata:
        name: Team:Platform
      spec: {}
      YAML
    SH
    create_import(cache_time: "1h")
    run!
    documents = YAML.load_stream(File.read(File.join(@dir, "generated", "teams.yaml")))
    team = documents.find { |d| d["kind"] == "BusinessActor" }
    marker = documents.find { |d| d["kind"] == "Import" }

    assert_equal "Import:Teams", team.dig("metadata", "annotations", "generated/script")
    assert marker.dig("metadata", "annotations", "generated/at")
    assert_empty run!.ran_imports, "the second run is served from the cache"
  end

  def test_only_listed_environment_variables_reach_the_program
    write_script(<<~SH)
      echo "listed=${ARCHSIGHT_TEST_LISTED:-} other=${ARCHSIGHT_TEST_OTHER:-} name=$ARCHSIGHT_IMPORT_NAME" > "$ARCHSIGHT_RESOURCES_DIR/env.txt"
    SH
    create_import(config: { "env" => "ARCHSIGHT_TEST_LISTED", "outputs" => "env.txt" })
    with_env("ARCHSIGHT_TEST_LISTED" => "yes", "ARCHSIGHT_TEST_OTHER" => "secret") { run! }

    assert_equal "listed=yes other= name=Import:Teams", File.read(File.join(@dir, "env.txt")).strip
    marker = YAML.load_stream(File.read(File.join(@dir, "generated", "teams.yaml"))).find { |d| d["kind"] == "Import" }

    assert_equal "env.txt", marker.dig("metadata", "annotations", "generated/outputs")
  end

  def test_a_failing_program_fails_the_import_with_its_error_output
    write_script("echo 'cannot reach the directory service' >&2\nexit 3\n")
    create_import

    error = assert_raises(Archsight::Import::ImportError) { run! }
    assert_includes error.message, "exit 3"
    assert_includes error.message, "cannot reach the directory service"
  end

  private

  def write_script(body)
    FileUtils.mkdir_p(File.join(@dir, "importers"))
    File.write(File.join(@dir, "importers", "teams.sh"), "#!/bin/sh\nset -e\n#{body}")
  end

  def create_import(cache_time: nil, config: {})
    annotations = { "import/handler" => "command", "import/outputPath" => "generated/teams.yaml",
                    "import/config/command" => "sh importers/teams.sh", "import/config/workdir" => "." }
    annotations["import/cacheTime"] = cache_time if cache_time
    config.each { |key, value| annotations["import/config/#{key}"] = value }
    document = { "apiVersion" => "architecture/v1alpha1", "kind" => "Import",
                 "metadata" => { "name" => "Import:Teams", "annotations" => annotations }, "spec" => {} }
    File.write(File.join(@dir, "imports", "teams.yaml"), YAML.dump(document))
  end

  def run!
    db = Archsight::Database.new(@dir, verbose: false, verify: true, compute_annotations: false)
    Archsight::Import::Executor.new(database: db, resources_dir: @dir, output: StringIO.new).tap(&:run!)
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
