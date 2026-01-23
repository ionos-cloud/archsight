# frozen_string_literal: true

require "test_helper"
require "archsight/web/editor/form_builder"

class FormBuilderTest < Minitest::Test
  def test_fields_for_returns_array_of_fields
    fields = Archsight::Web::Editor::FormBuilder.fields_for("TechnologyArtifact")

    assert_instance_of Array, fields
    assert_predicate fields, :any?
    assert_kind_of Archsight::Web::Editor::FormBuilder::Field, fields.first
  end

  def test_field_for_enum_returns_select
    fields = Archsight::Web::Editor::FormBuilder.fields_for("TechnologyArtifact")
    artifact_type_field = fields.find { |f| f.key == "artifact/type" }

    assert artifact_type_field
    assert_predicate artifact_type_field, :select?
    assert artifact_type_field.options
    assert_includes artifact_type_field.options, "repo"
  end

  def test_field_for_integer_returns_number_input
    fields = Archsight::Web::Editor::FormBuilder.fields_for("TechnologyArtifact")
    contributors_field = fields.find { |f| f.key == "activity/contributors/6m" }

    assert contributors_field
    assert_predicate contributors_field, :number?
    assert_equal "1", contributors_field.step
  end

  def test_field_for_float_returns_number_input_with_decimal_step
    fields = Archsight::Web::Editor::FormBuilder.fields_for("TechnologyArtifact")
    cost_field = fields.find { |f| f.key == "scc/estimatedCost" }

    assert cost_field
    assert_predicate cost_field, :number?
    assert_equal "0.01", cost_field.step
  end

  def test_field_for_uri_returns_url_input
    fields = Archsight::Web::Editor::FormBuilder.fields_for("TechnologyArtifact")
    git_field = fields.find { |f| f.key == "repository/git" }

    assert git_field
    assert_predicate git_field, :url?
  end

  def test_field_for_markdown_returns_textarea
    fields = Archsight::Web::Editor::FormBuilder.fields_for("TechnologyArtifact")
    description_field = fields.find { |f| f.key == "architecture/description" }

    assert description_field
    assert_predicate description_field, :textarea?
  end

  def test_excludes_pattern_annotations
    fields = Archsight::Web::Editor::FormBuilder.fields_for("TechnologyArtifact")
    pattern_fields = fields.select { |f| f.key.include?("*") }

    assert_empty pattern_fields
  end

  def test_field_has_title_and_description
    fields = Archsight::Web::Editor::FormBuilder.fields_for("TechnologyArtifact")
    artifact_type_field = fields.find { |f| f.key == "artifact/type" }

    assert artifact_type_field.title
    refute_empty artifact_type_field.title
    assert artifact_type_field.description
  end

  def test_determine_input_type_for_enum_annotation
    # Use a real annotation from TechnologyArtifact that has enum
    annotation = Archsight::Resources["TechnologyArtifact"].annotations.find { |a| a.key == "artifact/type" }
    input_type = Archsight::Web::Editor::FormBuilder.determine_input_type(annotation)

    assert_equal :select, input_type
  end

  def test_determine_input_type_for_integer_annotation
    # Use a real annotation from TechnologyArtifact with Integer type
    annotation = Archsight::Resources["TechnologyArtifact"].annotations.find { |a| a.key == "activity/contributors/6m" }
    input_type = Archsight::Web::Editor::FormBuilder.determine_input_type(annotation)

    assert_equal :number, input_type
  end

  def test_determine_input_type_for_uri_annotation
    # Use a real annotation from TechnologyArtifact with URI type
    annotation = Archsight::Resources["TechnologyArtifact"].annotations.find { |a| a.key == "repository/git" }
    input_type = Archsight::Web::Editor::FormBuilder.determine_input_type(annotation)

    assert_equal :url, input_type
  end

  def test_determine_input_type_for_markdown_annotation
    # Use a real annotation from TechnologyArtifact with markdown format
    annotation = Archsight::Resources["TechnologyArtifact"].annotations.find { |a| a.key == "architecture/description" }
    input_type = Archsight::Web::Editor::FormBuilder.determine_input_type(annotation)

    assert_equal :textarea, input_type
  end

  def test_determine_step_for_integer_annotation
    annotation = Archsight::Resources["TechnologyArtifact"].annotations.find { |a| a.key == "activity/contributors/6m" }
    step = Archsight::Web::Editor::FormBuilder.determine_step(annotation)

    assert_equal "1", step
  end

  def test_determine_step_for_float_annotation
    annotation = Archsight::Resources["TechnologyArtifact"].annotations.find { |a| a.key == "scc/estimatedCost" }
    step = Archsight::Web::Editor::FormBuilder.determine_step(annotation)

    assert_equal "0.01", step
  end

  def test_determine_step_for_string_annotation
    # Use an annotation without numeric type
    annotation = Archsight::Resources["TechnologyArtifact"].annotations.find { |a| a.key == "artifact/type" }
    step = Archsight::Web::Editor::FormBuilder.determine_step(annotation)

    assert_nil step
  end
end
