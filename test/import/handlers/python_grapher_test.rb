# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/handlers/python_grapher"
require "archsight/import/progress"

class PythonGrapherTest < Minitest::Test
  def setup
    skip "python3 not available" unless system("python3 --version", out: File::NULL, err: File::NULL)
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  def test_single_package_generates_dot_graph
    repo = Dir.mktmpdir
    begin
      write_file(repo, "mypkg/__init__.py", "")
      write_file(repo, "mypkg/core.py", "from mypkg import utils")
      write_file(repo, "mypkg/utils.py", "")

      handler = create_handler(path: repo)
      handler.execute

      output = read_output(handler)
      assert_includes output, "digraph"
      assert_includes output, "core"
      assert_includes output, "utils"
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_dependency_edge_appears_in_dot
    repo = Dir.mktmpdir
    begin
      write_file(repo, "mypkg/__init__.py", "")
      write_file(repo, "mypkg/core.py", "from mypkg import utils")
      write_file(repo, "mypkg/utils.py", "")

      handler = create_handler(path: repo)
      handler.execute

      dot = read_dot_annotation(handler)
      assert_match(/"core"\s*->\s*"utils"/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_no_packages_writes_self_marker_only
    repo = Dir.mktmpdir
    begin
      write_file(repo, "README.md", "# hello")

      handler = create_handler(path: repo)
      handler.execute

      output = read_output(handler)
      resources = YAML.load_stream(output)
      kinds = resources.map { |r| r["kind"] }
      assert_equal ["Import"], kinds
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_root_is_package
    repo = Dir.mktmpdir
    begin
      write_file(repo, "__init__.py", "")
      write_file(repo, "core.py", "")

      handler = create_handler(path: repo)
      handler.execute

      output = read_output(handler)
      assert_includes output, "TechnologyArtifact"
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_skips_test_and_vendor_directories
    repo = Dir.mktmpdir
    begin
      write_file(repo, "mypkg/__init__.py", "")
      write_file(repo, "mypkg/core.py", "")
      write_file(repo, "tests/__init__.py", "")
      write_file(repo, "tests/test_core.py", "from mypkg import core")
      write_file(repo, "vendor/__init__.py", "")

      handler = create_handler(path: repo)
      handler.execute

      dot = read_dot_annotation(handler)
      refute_includes dot, "tests"
      refute_includes dot, "vendor"
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_missing_path_raises_error
    handler = create_handler(path: nil)
    assert_raises(RuntimeError) { handler.execute }
  end

  def test_nonexistent_path_raises_error
    handler = create_handler(path: "/nonexistent/path/that/does/not/exist")
    assert_raises(RuntimeError) { handler.execute }
  end

  def test_trivial_init_files_not_shown_as_nodes
    repo = Dir.mktmpdir
    begin
      write_file(repo, "mypkg/__init__.py", "")
      write_file(repo, "mypkg/sub/__init__.py", "")
      write_file(repo, "mypkg/sub/worker.py", "")

      handler = create_handler(path: repo)
      handler.execute

      dot = read_dot_annotation(handler)
      refute_match(/"mypkg"\s*\[/, dot)
      refute_match(/"sub"\s*\[/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_nontrivial_init_file_kept_as_node
    repo = Dir.mktmpdir
    begin
      write_file(repo, "mypkg/__init__.py", "class Config:\n    pass\n")
      write_file(repo, "mypkg/core.py", "")

      handler = create_handler(path: repo)
      handler.execute

      dot = read_dot_annotation(handler)
      assert_match(/"mypkg"\s*\[/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_multi_package_generates_clustered_graph
    repo = Dir.mktmpdir
    begin
      write_file(repo, "pkga/__init__.py", "")
      write_file(repo, "pkga/service.py", "from pkgb import utils")
      write_file(repo, "pkgb/__init__.py", "")
      write_file(repo, "pkgb/utils.py", "")

      handler = create_handler(path: repo)
      handler.execute

      dot = read_dot_annotation(handler)
      assert_includes dot, "cluster"
      assert_match(/pkga|pkgb/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  private

  def write_file(base, rel_path, content)
    full = File.join(base, rel_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  def create_handler(path:)
    annotations = { "import/handler" => "python-grapher" }
    annotations["import/config/path"] = path if path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:PythonGrapher:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockPythonImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::PythonGrapher.new(
      import_resource,
      database: nil,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def output_path
    File.join(@resources_dir, "generated", "Import_PythonGrapher_test.yaml")
  end

  def read_output(_handler)
    File.read(output_path)
  end

  def read_dot_annotation(_handler)
    resources = YAML.load_stream(read_output(_handler))
    artifact = resources.find { |r| r["kind"] == "TechnologyArtifact" }
    artifact&.dig("metadata", "annotations", "architecture/python/modules") || ""
  end

  # Mock import resource matching the pattern used across handler tests
  class MockPythonImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/python-grapher-test.yaml")
    end
  end
end
