# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "archsight/import/handlers/java_grapher"
require "archsight/import/progress"

class JavaGrapherTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@resources_dir)
  end

  def test_single_module_generates_dot_graph
    repo = Dir.mktmpdir
    begin
      write_java(repo, "src/main/java/com/example/core/Core.java", "com.example.core")
      write_java(repo, "src/main/java/com/example/util/Util.java", "com.example.util")

      dot = run_grapher(repo)

      assert_includes dot, "digraph"
      assert_match(/core|util/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_dependency_edge_appears
    repo = Dir.mktmpdir
    begin
      write_java(repo, "src/main/java/com/example/core/Core.java", "com.example.core",
                 imports: ["com.example.util.Util"])
      write_java(repo, "src/main/java/com/example/util/Util.java", "com.example.util")

      dot = run_grapher(repo)

      assert_match(/"core"\s*->\s*"util"/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_skips_test_directory
    repo = Dir.mktmpdir
    begin
      write_java(repo, "src/main/java/com/example/service/Service.java", "com.example.service")
      write_java(repo, "src/test/java/com/example/service/ServiceTest.java", "com.example.service")

      dot = run_grapher(repo)

      refute_match(/ServiceTest/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_no_java_files_writes_self_marker_only
    repo = Dir.mktmpdir
    begin
      File.write(File.join(repo, "README.md"), "# hello")

      output = run_full_handler(repo)
      resources = YAML.load_stream(output)

      assert_equal(["Import"], resources.map { |r| r["kind"] })
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_multi_module_maven
    repo = Dir.mktmpdir
    begin
      write_file(repo, "pom.xml", <<~XML)
        <project>
          <modules>
            <module>api</module>
            <module>core</module>
          </modules>
        </project>
      XML
      write_file(repo, "api/pom.xml", "<project/>")
      write_file(repo, "core/pom.xml", "<project/>")
      write_java(repo, "api/src/main/java/com/example/api/Api.java", "com.example.api")
      write_java(repo, "core/src/main/java/com/example/core/Core.java", "com.example.core")

      dot = run_grapher(repo)

      assert_includes dot, "digraph"
      assert_match(/cluster/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_external_imports_filtered
    repo = Dir.mktmpdir
    begin
      write_java(repo, "src/main/java/com/example/service/Service.java", "com.example.service",
                 imports: ["java.util.List", "org.springframework.stereotype.Component"])

      dot = run_grapher(repo)

      refute_match(%r{java/util}, dot)
      refute_match(/springframework/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_skips_target_directory
    repo = Dir.mktmpdir
    begin
      write_java(repo, "src/main/java/com/example/service/Service.java", "com.example.service")
      write_java(repo, "target/generated/com/example/gen/Gen.java", "com.example.gen")

      dot = run_grapher(repo)

      refute_match(%r{com/example/gen}, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_wildcard_import_resolved
    repo = Dir.mktmpdir
    begin
      write_java(repo, "src/main/java/com/example/core/Core.java", "com.example.core",
                 imports: ["com.example.util.*"])
      write_java(repo, "src/main/java/com/example/util/Util.java", "com.example.util")

      dot = run_grapher(repo)

      assert_match(/"core"\s*->\s*"util"/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_parent_package_node_visible_and_has_incoming_edge
    repo = Dir.mktmpdir
    begin
      # core has direct files AND a sub-package; util imports from core directly
      write_java(repo, "src/main/java/com/example/core/Core.java", "com.example.core")
      write_java(repo, "src/main/java/com/example/core/sub/Sub.java", "com.example.core.sub")
      write_java(repo, "src/main/java/com/example/util/Util.java", "com.example.util",
                 imports: ["com.example.core.Core"])

      dot = run_grapher(repo)
      # core package node must be visible (not suppressed by init_node)
      assert_match(/"core"\s*\[/, dot)
      # edge from util to core must exist (not suppressed by has_children)
      assert_match(/"util"\s*->\s*"core"/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_main_node_detected
    repo = Dir.mktmpdir
    begin
      write_java(repo, "src/main/java/com/example/app/Application.java", "com.example.app",
                 imports: ["com.example.service.MyService"])
      write_file(repo, "src/main/java/com/example/app/Application.java",
                 "package com.example.app;\nimport com.example.service.MyService;\n" \
                 "public class Application {\n  public static void main(String[] args) {}\n}\n")
      write_java(repo, "src/main/java/com/example/service/MyService.java", "com.example.service")

      dot = run_grapher(repo)

      assert_match(/"main"\s*\[/, dot)
      assert_match(/"main"\s*->\s*"app"/, dot)
    ensure
      FileUtils.rm_rf(repo)
    end
  end

  def test_deep_packages_folded_to_max_depth
    repo = Dir.mktmpdir
    begin
      # A shallow package anchors common prefix at com/example
      write_java(repo, "src/main/java/com/example/service/Service.java", "com.example.service")
      # Depth-3 packages should fold into dto/common (depth 2 from mod_name com/example)
      write_java(repo, "src/main/java/com/example/dto/common/collection/CollectionDto.java",
                 "com.example.dto.common.collection")
      write_java(repo, "src/main/java/com/example/dto/common/pagination/PageDto.java",
                 "com.example.dto.common.pagination")

      dot = run_grapher(repo)
      # depth-3 packages should be folded; neither original leaf should appear as its own node
      refute_match(/"collection"\s*\[/, dot)
      refute_match(/"pagination"\s*\[/, dot)
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

  def write_java(base, rel_path, pkg, imports: [])
    import_lines = imports.map { |i| "import #{i};" }.join("\n")
    content = "package #{pkg};\n#{import_lines}\npublic class #{File.basename(rel_path, ".java")} {}\n"
    write_file(base, rel_path, content)
  end

  def create_handler(path:)
    annotations = { "import/handler" => "java-grapher" }
    annotations["import/config/path"] = path if path

    import_raw = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "Import",
      "metadata" => {
        "name" => "Import:JavaGrapher:test",
        "annotations" => annotations
      },
      "spec" => {}
    }

    import_resource = MockJavaImport.new(import_raw)
    progress = Archsight::Import::Progress.new(output: StringIO.new)
    Archsight::Import::Handlers::JavaGrapher.new(
      import_resource,
      database: nil,
      resources_dir: @resources_dir,
      progress: progress
    )
  end

  def output_path
    File.join(@resources_dir, "generated", "modules.yaml")
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
    artifact&.dig("metadata", "annotations", "architecture/java/modules") || ""
  end

  class MockJavaImport
    attr_reader :raw, :name, :annotations, :path_ref

    PathRef = Struct.new(:path)

    def initialize(raw)
      @raw = raw
      @name = raw.dig("metadata", "name")
      @annotations = raw.dig("metadata", "annotations") || {}
      @path_ref = PathRef.new("/tmp/java-grapher-test.yaml")
    end
  end
end
