# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/helpers"
require "tmpdir"
require "fileutils"

class DiagramIncludesLoaderTest < Minitest::Test
  YAML_TEMPLATE = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: %<name>s
      annotations:
    %<annotations>s
    spec: {}
  YAML

  def setup
    @dir = Dir.mktmpdir
    @outside = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "parts"))
    File.write(File.join(@dir, "parts", "db.asd"), %(component "db" { }\n))
    File.write(File.join(@dir, "parts", "notes.md"), "x")
    File.write(File.join(@dir, ".hidden.asd"), "x")
    File.write(File.join(@outside, "secret.asd"), %(component "secret" { }\n))
    File.symlink(File.join(@outside, "secret.asd"), File.join(@dir, "link.asd"))
    write_component("Shared", %(      architecture/diagram: |\n        component "shared" { }))
    write_component("NoDiagram", "      architecture/description: hi")
    @db = Archsight::Database.new(@dir, verbose: false, compute_annotations: false).tap(&:reload!)
    @loader = Archsight::Helpers::DiagramIncludes.for(@db)
  end

  def teardown
    FileUtils.remove_entry(@dir)
    FileUtils.remove_entry(@outside)
  end

  def write_component(name, annotations)
    File.write(File.join(@dir, "#{name}.yaml"), format(YAML_TEMPLATE, name: name, annotations: annotations))
  end

  def test_archsight_loads_the_diagram_annotation_of_a_resource
    assert_includes @loader.call("archsight://ApplicationComponent/Shared"), %(component "shared")
  end

  def test_archsight_failures
    assert_equal :missing, @loader.call("archsight://ApplicationComponent/Nope")
    assert_equal :missing, @loader.call("archsight://ApplicationComponent/NoDiagram")
    assert_equal :invalid, @loader.call("archsight://NoSuchKind/x")
    assert_equal :invalid, @loader.call("archsight://ApplicationComponent")
  end

  def test_file_is_relative_to_the_resources_directory
    assert_equal %(component "db" { }\n), @loader.call("file://parts/db.asd")
    assert_equal %(component "db" { }\n), @loader.call("file://parts/../parts/db.asd")
  end

  def test_file_never_leaves_the_resources_directory_or_reads_other_things
    assert_equal :missing, @loader.call("file://../secret.asd")
    assert_equal :missing, @loader.call("file://parts/../../x.asd")
    assert_equal :forbidden, @loader.call("file:///etc/passwd.asd")
    assert_equal :missing, @loader.call("file://link.asd") # a symlink out
    assert_equal :missing, @loader.call("file://.hidden.asd")
    assert_equal :invalid, @loader.call("file://parts/notes.md")
    assert_equal :missing, @loader.call("file://parts/none.asd")
  end

  def test_other_schemes_are_invalid
    assert_equal :invalid, @loader.call("https://example.com/x.asd")
    assert_equal :invalid, @loader.call("parts/db.asd")
  end

  def test_without_a_database_only_files_load
    loader = Archsight::Helpers::DiagramIncludes.new(nil, resources_dir: @dir)

    assert_equal :forbidden, loader.call("archsight://ApplicationComponent/Shared")
    assert_kind_of String, loader.call("file://parts/db.asd")
  end

  def test_the_fingerprint_follows_the_included_diagram
    source = %(include "archsight://ApplicationComponent/Shared"\n)
    before = Archsight::Helpers::DiagramBlocks.fingerprint(source, includes: @loader)
    write_component("Shared", %(      architecture/diagram: |\n        component "changed" { }))
    after = Archsight::Helpers::DiagramBlocks.fingerprint(source, includes: Archsight::Helpers::DiagramIncludes.for(Archsight::Database.new(@dir, verbose: false, compute_annotations: false).tap(&:reload!)))

    refute_equal before, after
  end

  def test_the_web_render_includes_the_diagram
    html = Archsight::Helpers::DiagramBlocks.render_diagram(%(include "file://parts/db.asd"\n), includes: @loader)

    assert_includes html, "asd-node-db"
    refute_includes html, "asd-diagram-error"
  end

  def test_a_broken_include_renders_the_error_box
    html = Archsight::Helpers::DiagramBlocks.render_diagram(%(include "file://nope.asd"\n), includes: @loader)

    assert_includes html, "asd-diagram-error"
    assert_includes html, "not found"
  end

  def test_the_linter_reports_a_broken_include_and_warns_about_ignored_statements
    File.write(File.join(@dir, "parts", "flow.asd"), %(theme "compact"\ncomponent "f" { }\n))
    write_component("Broken", %(      architecture/diagram: |\n        include "file://nope.asd"))
    write_component("Warn", %(      architecture/diagram: |\n        group "g" { include "file://parts/flow.asd" }))
    db = Archsight::Database.new(@dir, verbose: false, compute_annotations: false).tap(&:reload!)
    linter = Archsight::Linter.new(db)
    errors = linter.validate

    assert(errors.any? { |e| e.include?("Diagram error") && e.include?("nope.asd") })
    assert(linter.warnings.any? { |w| w.include?("theme setting") && w.include?("flow.asd") })
  end
end
