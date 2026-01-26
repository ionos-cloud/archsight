# frozen_string_literal: true

require_relative "test_helper"
require "archsight/editor"

class EditorTest < Minitest::Test
  def test_build_resource_creates_valid_yaml
    resource = Archsight::Editor.build_resource(
      kind: "TechnologyArtifact",
      name: "my-artifact",
      annotations: { "artifact/type" => "repo" }
    )

    assert_equal "architecture/v1alpha1", resource["apiVersion"]
    assert_equal "TechnologyArtifact", resource["kind"]
    assert_equal "my-artifact", resource["metadata"]["name"]
    assert_equal "repo", resource["metadata"]["annotations"]["artifact/type"]
  end

  def test_build_resource_handles_empty_annotations
    resource = Archsight::Editor.build_resource(
      kind: "TechnologyArtifact",
      name: "my-artifact",
      annotations: {}
    )

    refute resource["metadata"].key?("annotations")
  end

  def test_build_resource_filters_empty_values
    resource = Archsight::Editor.build_resource(
      kind: "TechnologyArtifact",
      name: "my-artifact",
      annotations: { "artifact/type" => "repo", "empty" => "", "nil_value" => nil, "whitespace" => "   " }
    )

    assert_equal 1, resource["metadata"]["annotations"].size
    assert_equal "repo", resource["metadata"]["annotations"]["artifact/type"]
  end

  def test_build_resource_handles_relations
    resource = Archsight::Editor.build_resource(
      kind: "TechnologyArtifact",
      name: "my-artifact",
      relations: [
        { verb: "servedBy", kind: "TechnologyArtifact", names: ["other-artifact"] },
        { verb: "maintainedBy", kind: "BusinessActor", names: %w[person1 person2] }
      ]
    )

    assert resource["spec"]
    # Spec uses relation_name keys, not target class names
    assert_equal ["other-artifact"], resource["spec"]["servedBy"]["technologyComponents"]
    assert_equal %w[person1 person2], resource["spec"]["maintainedBy"]["businessActors"]
  end

  def test_build_resource_deduplicates_relation_names
    resource = Archsight::Editor.build_resource(
      kind: "TechnologyArtifact",
      name: "my-artifact",
      relations: [
        { verb: "servedBy", kind: "TechnologyArtifact", names: %w[artifact1 artifact1 artifact2] }
      ]
    )

    # Spec uses relation_name keys
    assert_equal %w[artifact1 artifact2], resource["spec"]["servedBy"]["technologyComponents"]
  end

  def test_build_resource_with_string_keys_in_relations
    resource = Archsight::Editor.build_resource(
      kind: "TechnologyArtifact",
      name: "my-artifact",
      relations: [
        { "verb" => "servedBy", "kind" => "TechnologyArtifact", "names" => ["other-artifact"] }
      ]
    )

    # Spec uses relation_name keys
    assert_equal ["other-artifact"], resource["spec"]["servedBy"]["technologyComponents"]
  end

  def test_build_resource_skips_empty_relations
    resource = Archsight::Editor.build_resource(
      kind: "TechnologyArtifact",
      name: "my-artifact",
      relations: [
        { verb: "", kind: "TechnologyArtifact", names: ["artifact"] },
        { verb: "servedBy", kind: "", names: ["artifact"] },
        { verb: "servedBy", kind: "TechnologyArtifact", names: [] }
      ]
    )

    refute resource.key?("spec")
  end

  def test_validate_returns_errors_for_missing_name
    result = Archsight::Editor.validate("TechnologyArtifact", name: "", annotations: {})

    refute result[:valid]
    assert result[:errors]["name"]
  end

  def test_validate_returns_errors_for_name_with_spaces
    result = Archsight::Editor.validate("TechnologyArtifact", name: "my artifact", annotations: {})

    refute result[:valid]
    assert_includes result[:errors]["name"].first, "spaces"
  end

  def test_validate_returns_errors_for_invalid_enum
    result = Archsight::Editor.validate(
      "TechnologyArtifact",
      name: "my-artifact",
      annotations: { "artifact/type" => "invalid_type" }
    )

    refute result[:valid]
    assert result[:errors]["artifact/type"]
    assert_includes result[:errors]["artifact/type"].first, "invalid value"
  end

  def test_validate_returns_errors_for_invalid_integer
    result = Archsight::Editor.validate(
      "TechnologyArtifact",
      name: "my-artifact",
      annotations: { "activity/contributors/6m" => "not_a_number" }
    )

    refute result[:valid]
    assert result[:errors]["activity/contributors/6m"]
  end

  def test_validate_accepts_uri_values
    # NOTE: URI validation in annotation module currently doesn't validate
    # because URI is a Module, not a Class. This test documents actual behavior.
    result = Archsight::Editor.validate(
      "TechnologyArtifact",
      name: "my-artifact",
      annotations: { "repository/git" => "https://github.com/example/repo" }
    )

    assert result[:valid]
  end

  def test_validate_returns_valid_for_correct_data
    result = Archsight::Editor.validate(
      "TechnologyArtifact",
      name: "my-artifact",
      annotations: {
        "artifact/type" => "repo",
        "repository/git" => "https://github.com/example/repo"
      }
    )

    assert result[:valid]
    assert_empty result[:errors]
  end

  def test_validate_skips_empty_values
    result = Archsight::Editor.validate(
      "TechnologyArtifact",
      name: "my-artifact",
      annotations: { "artifact/type" => "" }
    )

    assert result[:valid]
    assert_empty result[:errors]
  end

  def test_to_yaml_generates_valid_yaml_string
    resource = Archsight::Editor.build_resource(
      kind: "TechnologyArtifact",
      name: "my-artifact"
    )

    yaml = Archsight::Editor.to_yaml(resource)

    assert_instance_of String, yaml
    assert yaml.start_with?("---")

    parsed = YAML.safe_load(yaml)

    assert_equal "my-artifact", parsed["metadata"]["name"]
  end

  def test_editable_annotations_excludes_pattern_annotations
    annotations = Archsight::Editor.editable_annotations("TechnologyArtifact")

    # Pattern annotations like "link/*" should be excluded
    pattern_keys = annotations.map(&:key).select { |k| k.include?("*") }

    assert_empty pattern_keys
  end

  def test_editable_annotations_excludes_system_managed_fields
    annotations = Archsight::Editor.editable_annotations("TechnologyArtifact")
    keys = annotations.map(&:key)

    # System-managed fields should be excluded
    refute_includes keys, "git/updatedAt"
    refute_includes keys, "git/updatedBy"
    refute_includes keys, "git/reviewedAt"
    refute_includes keys, "git/reviewedBy"
    refute_includes keys, "generated/script"
    refute_includes keys, "generated/at"
    refute_includes keys, "generated/configHash"
  end

  def test_relation_verbs_returns_unique_sorted_verbs
    verbs = Archsight::Editor.relation_verbs("TechnologyArtifact")

    assert_instance_of Array, verbs
    assert_predicate verbs, :any?
    assert_equal verbs.sort, verbs
    assert_equal verbs.uniq, verbs
  end

  def test_target_kinds_for_verb_returns_valid_kinds
    kinds = Archsight::Editor.target_kinds_for_verb("TechnologyArtifact", "servedBy")

    assert_instance_of Array, kinds
    # servedBy relation targets TechnologyArtifact
    assert_includes kinds, "TechnologyArtifact"
  end

  def test_relation_name_for_returns_relation_name
    name = Archsight::Editor.relation_name_for("TechnologyArtifact", "servedBy", "TechnologyArtifact")

    assert_equal "technologyComponents", name
  end

  def test_relation_name_for_returns_nil_for_invalid_combination
    name = Archsight::Editor.relation_name_for("TechnologyArtifact", "servedBy", "BusinessActor")

    assert_nil name
  end

  def test_target_kinds_for_verb_returns_empty_for_invalid_verb
    kinds = Archsight::Editor.target_kinds_for_verb("TechnologyArtifact", "invalidVerb")

    assert_empty kinds
  end
end

class FileWriterTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_replace_document_single_document_file
    file_path = File.join(@temp_dir, "single.yaml")
    File.write(file_path, <<~YAML)
      ---
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: old-name
    YAML

    new_yaml = <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: new-name
    YAML

    Archsight::Editor::FileWriter.replace_document(
      path: file_path,
      start_line: 1,
      new_yaml: new_yaml
    )

    result = File.read(file_path)

    assert_includes result, "new-name"
    refute_includes result, "old-name"
  end

  def test_replace_document_multi_document_file
    file_path = File.join(@temp_dir, "multi.yaml")
    File.write(file_path, <<~YAML)
      ---
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: first-resource
      ---
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: second-resource
      ---
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: third-resource
    YAML

    new_yaml = <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: updated-second
    YAML

    Archsight::Editor::FileWriter.replace_document(
      path: file_path,
      start_line: 7,
      new_yaml: new_yaml
    )

    result = File.read(file_path)

    assert_includes result, "first-resource"
    assert_includes result, "updated-second"
    assert_includes result, "third-resource"
    refute_includes result, "second-resource"
  end

  def test_replace_document_file_not_found
    error = assert_raises(Archsight::Editor::FileWriter::WriteError) do
      Archsight::Editor::FileWriter.replace_document(
        path: "/nonexistent/path.yaml",
        start_line: 1,
        new_yaml: "---\ntest: value\n"
      )
    end

    assert_includes error.message, "File not found"
  end

  def test_replace_document_file_not_writable
    file_path = File.join(@temp_dir, "readonly.yaml")
    File.write(file_path, "---\ntest: value\n")
    File.chmod(0o444, file_path)

    error = assert_raises(Archsight::Editor::FileWriter::WriteError) do
      Archsight::Editor::FileWriter.replace_document(
        path: file_path,
        start_line: 1,
        new_yaml: "---\nnew: value\n"
      )
    end

    assert_includes error.message, "not writable"
  ensure
    File.chmod(0o644, file_path) if File.exist?(file_path)
  end

  def test_replace_document_line_beyond_eof
    file_path = File.join(@temp_dir, "short.yaml")
    File.write(file_path, "---\ntest: value\n")

    error = assert_raises(Archsight::Editor::FileWriter::WriteError) do
      Archsight::Editor::FileWriter.replace_document(
        path: file_path,
        start_line: 100,
        new_yaml: "---\nnew: value\n"
      )
    end

    assert_includes error.message, "beyond end of file"
  end

  def test_replace_document_adds_trailing_newline
    file_path = File.join(@temp_dir, "newline.yaml")
    File.write(file_path, "---\ntest: value\n")

    Archsight::Editor::FileWriter.replace_document(
      path: file_path,
      start_line: 1,
      new_yaml: "---\nnew: value" # No trailing newline
    )

    result = File.read(file_path)

    assert result.end_with?("\n")
  end

  def test_find_document_end_with_separator
    lines = [
      "---\n",
      "first: doc\n",
      "---\n",
      "second: doc\n"
    ]

    end_idx = Archsight::Editor::FileWriter.find_document_end(lines, 0)

    assert_equal 2, end_idx
  end

  def test_find_document_end_at_eof
    lines = [
      "---\n",
      "only: doc\n",
      "more: content\n"
    ]

    end_idx = Archsight::Editor::FileWriter.find_document_end(lines, 0)

    assert_equal 3, end_idx
  end

  def test_replace_document_last_document_in_file
    file_path = File.join(@temp_dir, "last.yaml")
    File.write(file_path, <<~YAML)
      ---
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: first
      ---
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: last
    YAML

    new_yaml = <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: TechnologyArtifact
      metadata:
        name: updated-last
    YAML

    Archsight::Editor::FileWriter.replace_document(
      path: file_path,
      start_line: 7,
      new_yaml: new_yaml
    )

    result = File.read(file_path)

    assert_includes result, "first"
    assert_includes result, "updated-last"
    refute_includes result, "name: last"
  end
end
