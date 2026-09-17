# frozen_string_literal: true

require "test_helper"
require "archsight/import"
require "archsight/import/shared_file_writer"
require "tmpdir"
require "fileutils"

class SharedFileWriterTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @writer = Archsight::Import::SharedFileWriter.new
  end

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  # append_yaml tests

  def test_append_yaml_creates_entry
    path = File.join(@tmpdir, "output.yaml")
    @writer.append_yaml(path, "key: value", sort_key: "A")
    @writer.close_all

    assert_path_exists path
    assert_equal "key: value\n", File.read(path)
  end

  def test_append_yaml_multiple_entries
    path = File.join(@tmpdir, "output.yaml")
    @writer.append_yaml(path, "first: 1", sort_key: "A")
    @writer.append_yaml(path, "second: 2", sort_key: "B")
    @writer.close_all

    content = File.read(path)

    assert_includes content, "first: 1"
    assert_includes content, "second: 2"
    assert_includes content, "---"
  end

  # close_all tests

  def test_close_all_writes_sorted_content
    path = File.join(@tmpdir, "sorted.yaml")
    @writer.append_yaml(path, "c_content: 3", sort_key: "C")
    @writer.append_yaml(path, "a_content: 1", sort_key: "A")
    @writer.append_yaml(path, "b_content: 2", sort_key: "B")
    @writer.close_all

    content = File.read(path)
    lines = content.split("\n")

    # First entry should be A (sorted), then B, then C
    assert_match(/a_content/, lines.first)
    assert_operator(lines.index { |l| l.include?("b_content") }, :>, lines.index { |l| l.include?("a_content") })
    assert_operator(lines.index { |l| l.include?("c_content") }, :>, lines.index { |l| l.include?("b_content") })
  end

  def test_close_all_with_empty_entries
    path = File.join(@tmpdir, "empty.yaml")

    # Just close without appending anything
    @writer.close_all

    refute_path_exists path
  end

  def test_nil_sort_key_goes_last
    path = File.join(@tmpdir, "nil_key.yaml")
    @writer.append_yaml(path, "nil_key: none", sort_key: nil)
    @writer.append_yaml(path, "a_key: first", sort_key: "A")
    @writer.append_yaml(path, "z_key: last", sort_key: "Z")
    @writer.close_all

    content = File.read(path)
    lines = content.split("\n")

    # A should come first, Z next, nil last
    a_idx = lines.index { |l| l.include?("a_key") }
    z_idx = lines.index { |l| l.include?("z_key") }
    nil_idx = lines.index { |l| l.include?("nil_key") }

    assert_operator(a_idx, :<, z_idx)
    assert_operator(z_idx, :<, nil_idx)
  end

  def test_adds_document_separator
    path = File.join(@tmpdir, "separator.yaml")
    @writer.append_yaml(path, "first: 1", sort_key: "A")
    @writer.append_yaml(path, "second: 2", sort_key: "B")
    @writer.close_all

    content = File.read(path)

    # Should have exactly one --- between documents
    assert_equal 1, content.scan("---").count
  end

  def test_skips_separator_if_content_has_one
    path = File.join(@tmpdir, "has_separator.yaml")
    @writer.append_yaml(path, "first: 1", sort_key: "A")
    @writer.append_yaml(path, "---\nsecond: 2", sort_key: "B")
    @writer.close_all

    content = File.read(path)

    # Should still have only one --- (from second content, not added)
    assert_equal 1, content.scan("---").count
  end

  def test_adds_trailing_newline
    path = File.join(@tmpdir, "trailing.yaml")
    @writer.append_yaml(path, "no_newline: value", sort_key: "A")
    @writer.close_all

    content = File.read(path)

    assert content.end_with?("\n")
  end

  def test_preserves_existing_trailing_newline
    path = File.join(@tmpdir, "has_newline.yaml")
    @writer.append_yaml(path, "has_newline: value\n", sort_key: "A")
    @writer.close_all

    content = File.read(path)

    # Should not add double newlines
    assert content.end_with?("\n")
    refute content.end_with?("\n\n")
  end

  def test_creates_parent_directories
    path = File.join(@tmpdir, "nested", "deep", "output.yaml")
    @writer.append_yaml(path, "nested: value", sort_key: "A")
    @writer.close_all

    assert_path_exists path
    assert_equal "nested: value\n", File.read(path)
  end

  # Thread safety tests

  def test_thread_safety
    path = File.join(@tmpdir, "threaded.yaml")
    threads = []

    10.times do |i|
      threads << Thread.new do
        @writer.append_yaml(path, "item: #{i}", sort_key: format("key_%02d", i))
      end
    end

    threads.each(&:join)
    @writer.close_all

    content = File.read(path)

    # All items should be present
    10.times do |i|
      assert_includes content, "item: #{i}"
    end
  end

  def test_thread_safety_multiple_files
    paths = 3.times.map { |i| File.join(@tmpdir, "file_#{i}.yaml") }
    threads = []

    paths.each_with_index do |path, _file_idx|
      5.times do |item_idx|
        threads << Thread.new do
          @writer.append_yaml(path, "item: #{item_idx}", sort_key: format("key_%02d", item_idx))
        end
      end
    end

    threads.each(&:join)
    @writer.close_all

    paths.each do |path|
      assert_path_exists path
      content = File.read(path)

      5.times do |i|
        assert_includes content, "item: #{i}"
      end
    end
  end

  # Producer-aware merge tests

  def resource_doc(name, producer:)
    <<~YAML
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: #{name}
        annotations:
          generated/script: #{producer}
      spec: {}
    YAML
  end

  def test_preserves_existing_document_from_a_different_producer
    path = File.join(@tmpdir, "shared.yaml")
    File.write(path, resource_doc("Repo:example:cached", producer: "Import:Repo:github:example:cached"))

    @writer.append_yaml(path, resource_doc("Repo:example:fresh", producer: "Import:Repo:github:example:fresh"),
                        sort_key: "fresh", producer: "Import:Repo:github:example:fresh")
    @writer.close_all

    content = File.read(path)

    assert_includes content, "Repo:example:cached"
    assert_includes content, "Repo:example:fresh"
  end

  def test_replaces_existing_document_from_the_same_producer
    path = File.join(@tmpdir, "shared.yaml")
    File.write(path, resource_doc("Repo:example:old-name", producer: "Import:Repo:github:example:svc"))

    @writer.append_yaml(path, resource_doc("Repo:example:svc", producer: "Import:Repo:github:example:svc"),
                        sort_key: "svc", producer: "Import:Repo:github:example:svc")
    @writer.close_all

    content = File.read(path)

    refute_includes content, "old-name"
    assert_includes content, "Repo:example:svc"
  end

  def test_preserves_self_marker_import_document_by_its_own_name
    path = File.join(@tmpdir, "shared.yaml")
    self_marker = <<~YAML
      apiVersion: architecture/v1alpha1
      kind: Import
      metadata:
        name: Import:Repo:github:example:cached
        annotations:
          generated/at: "2026-01-01T00:00:00Z"
          generated/configHash: abc123
      spec: {}
    YAML
    File.write(path, self_marker)

    @writer.append_yaml(path, resource_doc("Repo:example:fresh", producer: "Import:Repo:github:example:fresh"),
                        sort_key: "fresh", producer: "Import:Repo:github:example:fresh")
    @writer.close_all

    content = File.read(path)

    assert_includes content, "Import:Repo:github:example:cached"
    assert_includes content, "Repo:example:fresh"
  end

  def test_close_all_clears_buffer
    path = File.join(@tmpdir, "clear.yaml")
    @writer.append_yaml(path, "first: 1", sort_key: "A")
    @writer.close_all

    # Append again after close_all
    @writer.append_yaml(path, "second: 2", sort_key: "B")
    @writer.close_all

    content = File.read(path)

    # Should only contain second entry (file overwritten)
    refute_includes content, "first: 1"
    assert_includes content, "second: 2"
  end
end
