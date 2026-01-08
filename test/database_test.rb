# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class DatabaseTest < Minitest::Test
  def setup
    @resources_dir = File.expand_path("../examples/archsight", __dir__)
    @db = Archsight::Database.new(@resources_dir, verbose: false)
    @db.reload!
  end

  def test_loads_instances
    refute_empty @db.instances
  end

  def test_instances_by_kind
    artifacts = @db.instances_by_kind("TechnologyArtifact")

    assert_kind_of Hash, artifacts
  end

  def test_instances_by_kind_nonexistent
    result = @db.instances_by_kind("NonexistentKind")

    assert_empty(result)
  end

  def test_instance_by_kind
    artifacts = @db.instances_by_kind("TechnologyArtifact")
    skip if artifacts.empty?

    name = artifacts.keys.first
    instance = @db.instance_by_kind("TechnologyArtifact", name)

    assert_equal name, instance.name
  end

  def test_query_returns_array
    result = @db.query("name =~ \".*\"")

    assert_kind_of Array, result
  end

  def test_query_by_name
    artifacts = @db.instances_by_kind("TechnologyArtifact")
    skip if artifacts.empty?

    name = artifacts.keys.first
    result = @db.query("name == \"#{name}\"")

    assert_equal 1, result.length
    assert_equal name, result.first.name
  end

  def test_instance_matches
    artifacts = @db.instances_by_kind("TechnologyArtifact")
    skip if artifacts.empty?

    instance = artifacts.values.first

    assert @db.instance_matches?(instance, "name =~ \".*\"")
  end

  def test_filters_for_kind_returns_array
    filters = @db.filters_for_kind("TechnologyArtifact")

    assert_kind_of Array, filters
  end

  def test_filters_for_nonexistent_kind
    filters = @db.filters_for_kind("NonexistentKind")

    assert_empty filters
  end

  def test_reload_clears_and_reloads
    original_count = @db.instances.values.sum(&:count)
    @db.reload!
    new_count = @db.instances.values.sum(&:count)

    assert_equal original_count, new_count
  end

  def test_raises_on_invalid_yaml
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "invalid.yaml"), "invalid: yaml: content: [")

      db = Archsight::Database.new(dir, verbose: false)
      assert_raises(Archsight::ResourceError) { db.reload! }
    end
  end

  def test_raises_on_invalid_api_version
    Dir.mktmpdir do |dir|
      yaml_content = <<~YAML
        ---
        apiVersion: invalid/v1
        kind: TechnologyArtifact
        metadata:
          name: Test
        spec: {}
      YAML
      File.write(File.join(dir, "test.yaml"), yaml_content)

      db = Archsight::Database.new(dir, verbose: false)
      assert_raises(Archsight::ResourceError) { db.reload! }
    end
  end

  def test_raises_on_missing_kind
    Dir.mktmpdir do |dir|
      yaml_content = <<~YAML
        ---
        apiVersion: architecture/v1alpha1
        metadata:
          name: Test
        spec: {}
      YAML
      File.write(File.join(dir, "test.yaml"), yaml_content)

      db = Archsight::Database.new(dir, verbose: false)
      assert_raises(Archsight::ResourceError) { db.reload! }
    end
  end

  def test_raises_on_invalid_kind
    Dir.mktmpdir do |dir|
      yaml_content = <<~YAML
        ---
        apiVersion: architecture/v1alpha1
        kind: NonexistentKind
        metadata:
          name: Test
        spec: {}
      YAML
      File.write(File.join(dir, "test.yaml"), yaml_content)

      db = Archsight::Database.new(dir, verbose: false)
      assert_raises(Archsight::ResourceError) { db.reload! }
    end
  end

  def test_raises_on_missing_name
    Dir.mktmpdir do |dir|
      yaml_content = <<~YAML
        ---
        apiVersion: architecture/v1alpha1
        kind: TechnologyArtifact
        metadata: {}
        spec: {}
      YAML
      File.write(File.join(dir, "test.yaml"), yaml_content)

      db = Archsight::Database.new(dir, verbose: false)
      assert_raises(Archsight::ResourceError) { db.reload! }
    end
  end

  # LineReference tests

  def test_line_reference_to_s
    ref = Archsight::LineReference.new("/path/to/file.yaml", 42)

    assert_equal "/path/to/file.yaml:42", ref.to_s
  end

  def test_line_reference_at_line
    ref = Archsight::LineReference.new("/path/to/file.yaml", 42)
    new_ref = ref.at_line(100)

    assert_equal 100, new_ref.line_no
    assert_equal ref.path, new_ref.path
  end

  # ResourceError tests

  def test_resource_error_includes_ref
    ref = Archsight::LineReference.new("/path/to/file.yaml", 42)
    error = Archsight::ResourceError.new("Something went wrong", ref)

    assert_includes error.to_s, "/path/to/file.yaml:42"
    assert_includes error.to_s, "Something went wrong"
  end

  # Database options

  def test_database_without_compute_annotations
    db = Archsight::Database.new(@resources_dir, verbose: false, compute_annotations: false)
    db.reload!

    assert_predicate db.instances, :any?
  end

  def test_database_without_verify
    db = Archsight::Database.new(@resources_dir, verbose: false, verify: false)
    db.reload!

    assert_predicate db.instances, :any?
  end
end
