# frozen_string_literal: true

require_relative "test_helper"
require "archsight/template"

class TemplateTest < Minitest::Test
  def test_generate_raises_for_unknown_kind
    assert_raises(RuntimeError) { Archsight::Template.generate("UnknownKind") }
  end

  def test_generate_returns_yaml_string
    output = Archsight::Template.generate("TechnologyArtifact")

    assert_instance_of String, output
    assert output.start_with?("---")
  end

  def test_generate_includes_api_version
    output = Archsight::Template.generate("TechnologyArtifact")
    yaml = YAML.safe_load(output)

    assert_equal "architecture/v1alpha1", yaml["apiVersion"]
  end

  def test_generate_includes_kind
    output = Archsight::Template.generate("TechnologyArtifact")
    yaml = YAML.safe_load(output)

    assert_equal "TechnologyArtifact", yaml["kind"]
  end

  def test_generate_includes_metadata_name_todo
    output = Archsight::Template.generate("TechnologyArtifact")
    yaml = YAML.safe_load(output)

    assert_equal "TODO", yaml["metadata"]["name"]
  end

  def test_generate_includes_annotations
    output = Archsight::Template.generate("TechnologyArtifact")
    yaml = YAML.safe_load(output)

    assert yaml["metadata"]["annotations"], "Expected annotations to be present"
    assert_predicate yaml["metadata"]["annotations"], :any?, "Expected at least one annotation"
  end

  def test_generate_includes_relations
    output = Archsight::Template.generate("TechnologyArtifact")
    yaml = YAML.safe_load(output)

    assert yaml["spec"], "Expected spec to be present"
  end

  def test_enum_annotation_uses_first_value
    output = Archsight::Template.generate("TechnologyArtifact")
    yaml = YAML.safe_load(output)
    # activity/status has enum: %w[active abandoned]
    assert_equal "active", yaml["metadata"]["annotations"]["activity/status"]
  end

  def test_all_resource_kinds_generate_valid_yaml
    Archsight::Resources.each do |kind|
      output = Archsight::Template.generate(kind.to_s)
      yaml = YAML.safe_load(output)

      assert_equal "architecture/v1alpha1", yaml["apiVersion"], "#{kind} should have correct apiVersion"
      assert_equal kind.to_s, yaml["kind"], "#{kind} should have correct kind"
      assert_equal "TODO", yaml["metadata"]["name"], "#{kind} should have TODO name"
    end
  end
end
