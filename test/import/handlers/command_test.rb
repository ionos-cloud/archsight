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

  # The program's documents go to the output file as written: a relation-only document that extends a hand-written
  # resource, and kinds without the `generated` annotations, must not be marked (they would fail lint)
  def test_the_documents_are_written_unchanged_and_the_marker_is_added
    write_script(<<~SH)
      cat > "$ARCHSIGHT_OUTPUT_PATH" <<YAML
      # written by the teams script
      apiVersion: architecture/v1alpha1
      kind: Location
      metadata:
        name: Location:Berlin
      spec: {}
      ---
      apiVersion: architecture/v1alpha1
      kind: BusinessActor
      metadata:
        name: Team:Platform
        annotations:
          generated/script: Import:Teams
      spec: {}
      YAML
    SH
    create_import(cache_time: "1h")
    run!
    text = File.read(File.join(@dir, "generated", "teams.yaml"))
    documents = YAML.load_stream(text)
    marker = documents.find { |d| d["kind"] == "Import" }

    assert text.start_with?("# written by the teams script\n"), "the program's text is kept as written"
    assert_nil documents.find { |d| d["kind"] == "Location" }.dig("metadata", "annotations")
    assert_equal "Import:Teams", documents.find { |d| d["kind"] == "BusinessActor" }.dig("metadata", "annotations", "generated/script")
    assert marker.dig("metadata", "annotations", "generated/at")
    assert_equal "generated/teams.yaml", marker.dig("metadata", "annotations", "generated/outputs")
    assert_empty run!.ran_imports, "the second run is served from the cache"
  end

  def test_a_new_run_replaces_the_output_and_a_moved_output_removes_the_old_file
    write_script("printf 'apiVersion: architecture/v1alpha1\\nkind: Location\\nmetadata:\\n  name: Location:Berlin\\nspec: {}\\n' > \"$ARCHSIGHT_OUTPUT_PATH\"\n")
    create_import
    run!
    run!

    assert_equal(1, YAML.load_stream(File.read(File.join(@dir, "generated", "teams.yaml"))).count { |d| d["kind"] == "Location" })

    create_import(output_path: "generated/people.yaml")
    run!

    refute_path_exists File.join(@dir, "generated", "teams.yaml")
    assert_path_exists File.join(@dir, "generated", "people.yaml")
  end

  def test_only_listed_environment_variables_reach_the_program
    write_script(<<~SH)
      echo "listed=${ARCHSIGHT_TEST_LISTED:-} other=${ARCHSIGHT_TEST_OTHER:-} name=$ARCHSIGHT_IMPORT_NAME" > "$ARCHSIGHT_RESOURCES_DIR/env.txt"
    SH
    create_import(config: { "env" => "ARCHSIGHT_TEST_LISTED", "outputs" => "env.txt" })
    with_env("ARCHSIGHT_TEST_LISTED" => "yes", "ARCHSIGHT_TEST_OTHER" => "secret") { run! }

    assert_equal "listed=yes other= name=Import:Teams", File.read(File.join(@dir, "env.txt")).strip
    marker = YAML.load_stream(File.read(File.join(@dir, "generated", "teams.yaml"))).find { |d| d["kind"] == "Import" }

    assert_equal "env.txt,generated/teams.yaml", marker.dig("metadata", "annotations", "generated/outputs")
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

  def create_import(cache_time: nil, config: {}, output_path: "generated/teams.yaml")
    annotations = { "import/handler" => "command", "import/outputPath" => output_path,
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
