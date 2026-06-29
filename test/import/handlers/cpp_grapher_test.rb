# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/handlers/cpp_grapher"
require "archsight/import/progress"

class CppGrapherTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  # ── Single project ────────────────────────────────────────────────────────

  def test_single_project_generates_dot_graph
    with_repo do |repo|
      write(repo, "CMakeLists.txt", cmake_lists("my_project"))
      write(repo, "src/engine.cpp", "")
      write(repo, "src/renderer.cpp", "")

      dot = run_grapher(repo)

      assert_includes dot, "digraph"
      assert_match(/engine|renderer/, dot)
    end
  end

  def test_cmake_project_name_used_as_module
    with_repo do |repo|
      write(repo, "CMakeLists.txt", cmake_lists("my_engine"))
      write(repo, "src/core.cpp", "")

      dot = run_grapher(repo)

      assert_includes dot, "my_engine"
    end
  end

  # ── Dependency edges ──────────────────────────────────────────────────────

  def test_dependency_edge_from_include
    with_repo do |repo|
      write(repo, "CMakeLists.txt", cmake_lists("my_project"))
      write(repo, "src/engine/physics.cpp", '#include "renderer/vulkan.h"')
      write(repo, "include/renderer/vulkan.h", "")

      dot = run_grapher(repo)
      # node IDs strip "my_project/" prefix
      assert_match(/"engine"\s*->\s*"renderer"/, dot)
    end
  end

  def test_system_include_produces_no_edge
    with_repo do |repo|
      write(repo, "CMakeLists.txt", cmake_lists("my_project"))
      write(repo, "src/core.cpp", "#include <vector>\n#include <string>\n")

      dot = run_grapher(repo)

      refute_match(/vector|string/, dot)
    end
  end

  def test_external_include_produces_no_edge
    with_repo do |repo|
      write(repo, "CMakeLists.txt", cmake_lists("my_project"))
      write(repo, "src/core.cpp", '#include "boost/algorithm/string.hpp"')

      dot = run_grapher(repo)

      refute_match(/boost/, dot)
    end
  end

  # ── File mapping ──────────────────────────────────────────────────────────

  def test_header_and_source_map_to_same_package
    with_repo do |repo|
      write(repo, "CMakeLists.txt", cmake_lists("my_project"))
      write(repo, "src/engine/core.cpp", "")
      write(repo, "include/engine/core.h", "")

      dot = run_grapher(repo)
      # Both files map to my_project/engine → single "engine" node definition
      assert_equal 1, dot.scan('"engine" [').length
    end
  end

  def test_main_cpp_deps_not_extracted
    with_repo do |repo|
      write(repo, "CMakeLists.txt", cmake_lists("my_project"))
      write(repo, "src/main.cpp", '#include "engine/core.h"')
      write(repo, "src/engine/core.cpp", "")

      dot = run_grapher(repo)
      # engine node exists but no hub-spoke edge from invisible root
      assert_match(/engine/, dot)
      refute_match(/"my_project"\s*->/, dot)
    end
  end

  # ── Deep file capping ─────────────────────────────────────────────────────

  def test_deep_files_capped_at_max_depth
    with_repo do |repo|
      write(repo, "CMakeLists.txt", cmake_lists("my_project"))
      write(repo, "src/network/http/server.cpp", "")
      write(repo, "src/network/http/client.cpp", "")

      dot = run_grapher(repo)
      # my_project/network/http is depth 3; MAX_PKG_DEPTH=2 folds to my_project/network
      refute_match(/"http"/, dot)
      assert_match(/network/, dot)
    end
  end

  # ── No C++ files ──────────────────────────────────────────────────────────

  def test_no_cpp_files_writes_self_marker_only
    with_repo do |repo|
      write(repo, "CMakeLists.txt", cmake_lists("empty_project"))
      write(repo, "README.md", "# hello")

      output = run_full_handler(repo)
      resources = YAML.load_stream(output)

      assert_equal(["Import"], resources.map { |r| r["kind"] })
    end
  end

  # ── Multi-project (CMake workspace) ──────────────────────────────────────

  def test_cmake_multi_project_discovers_subdirs
    with_repo do |repo|
      write(repo, "CMakeLists.txt", workspace_cmake(%w[client server]))
      write(repo, "client/CMakeLists.txt", cmake_lists("client"))
      write(repo, "client/src/handler.cpp", "")
      write(repo, "server/CMakeLists.txt", cmake_lists("server"))
      write(repo, "server/src/listener.cpp", "")

      dot = run_grapher(repo)

      assert_includes dot, "cluster"
      assert_match(/handler|listener/, dot)
    end
  end

  def test_cross_module_include_creates_edge
    with_repo do |repo|
      write(repo, "CMakeLists.txt", workspace_cmake(%w[client common]))
      write(repo, "client/CMakeLists.txt", cmake_lists("client"))
      write(repo, "client/src/handler.cpp", '#include "common/types.h"')
      write(repo, "common/CMakeLists.txt", cmake_lists("common"))
      write(repo, "common/include/common/types.h", "")

      dot = run_grapher(repo)
      # workspace: no common prefix; client/handler → "client_handler"
      # common/include/common/types.h → strips include/ prefix → common/types → "common_types"
      assert_match(/"client_handler"\s*->\s*"common_types"/, dot)
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

  def cmake_lists(project_name)
    "cmake_minimum_required(VERSION 3.10)\nproject(#{project_name})\n"
  end

  def workspace_cmake(subdirs)
    dirs = subdirs.map { |d| "add_subdirectory(#{d})" }.join("\n")
    "cmake_minimum_required(VERSION 3.10)\n#{dirs}\n"
  end

  def with_repo
    repo = Dir.mktmpdir
    yield repo
  ensure
    FileUtils.rm_rf(repo)
  end

  def create_handler(path:)
    annotations = { "import/handler" => "cpp-grapher" }
    annotations["import/config/path"] = path if path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:CppGrapher:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockCppImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::CppGrapher.new(
      import_resource,
      database: nil,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def output_path
    File.join(@resources_dir, "generated", "Import_CppGrapher_test.yaml")
  end

  def run_full_handler(path)
    handler = create_handler(path: path)
    handler.execute
    File.read(output_path)
  end

  def run_grapher(path)
    output = run_full_handler(path)
    resources = YAML.load_stream(output)
    artifact = resources.find { |r| r["kind"] == "TechnologyArtifact" }
    artifact&.dig("metadata", "annotations", "architecture/cpp/modules") || ""
  end

  class MockCppImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/cpp-grapher-test.yaml")
    end
  end
end
