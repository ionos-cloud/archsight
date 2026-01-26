# frozen_string_literal: true

require "test_helper"
require "rack/test"
require "archsight/web/application"

class EditorRoutesTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Archsight::Web::Application
  end

  def setup
    Archsight.resources_dir = File.expand_path("../../examples/archsight", __dir__)
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
  end

  # Create mode tests

  def test_get_new_form_renders
    get "/kinds/TechnologyArtifact/new"

    assert_predicate last_response, :ok?, "Expected 200, got #{last_response.status}"
    assert_includes last_response.body, "New TechnologyArtifact"
    assert_includes last_response.body, "form"
  end

  def test_get_new_form_includes_name_field
    get "/kinds/TechnologyArtifact/new"

    assert_predicate last_response, :ok?
    # HAML uses single quotes for attributes
    assert_includes last_response.body, "name='name'"
  end

  def test_get_new_form_includes_annotation_fields
    get "/kinds/TechnologyArtifact/new"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "artifact/type"
  end

  def test_get_new_form_404_for_unknown_kind
    get "/kinds/UnknownKind/new"

    assert_equal 404, last_response.status
  end

  def test_post_generate_with_valid_data_shows_yaml
    post "/kinds/TechnologyArtifact/generate", {
      "name" => "test-artifact",
      "annotations" => { "artifact/type" => "repo" }
    }

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "Generated YAML"
    assert_includes last_response.body, "test-artifact"
    assert_includes last_response.body, "apiVersion"
  end

  def test_post_generate_with_invalid_name_shows_errors
    post "/kinds/TechnologyArtifact/generate", {
      "name" => "",
      "annotations" => {}
    }

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "required"
  end

  def test_post_generate_with_name_with_spaces_shows_errors
    post "/kinds/TechnologyArtifact/generate", {
      "name" => "test artifact",
      "annotations" => {}
    }

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "spaces"
  end

  def test_post_generate_with_invalid_enum_shows_errors
    post "/kinds/TechnologyArtifact/generate", {
      "name" => "test-artifact",
      "annotations" => { "artifact/type" => "invalid_value" }
    }

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "invalid value"
  end

  # Edit mode tests

  def test_get_edit_form_loads_instance_values
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    instance_name = artifacts.keys.first
    get "/kinds/TechnologyArtifact/instances/#{instance_name}/edit"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "Edit TechnologyArtifact"
    assert_includes last_response.body, instance_name
  end

  def test_get_edit_form_404_for_unknown_instance
    get "/kinds/TechnologyArtifact/instances/nonexistent-instance-xyz/edit"

    assert_equal 404, last_response.status
  end

  def test_get_edit_form_404_for_unknown_kind
    get "/kinds/UnknownKind/instances/test/edit"

    assert_equal 404, last_response.status
  end

  def test_post_edit_generate_with_valid_data_shows_yaml
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    instance_name = artifacts.keys.first
    post "/kinds/TechnologyArtifact/instances/#{instance_name}/generate", {
      "name_field" => "updated-artifact",
      "annotations" => { "artifact/type" => "repo" }
    }

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "Generated YAML"
    assert_includes last_response.body, "updated-artifact"
  end

  # API tests

  def test_api_instances_returns_json
    get "/api/v1/editor/kinds/TechnologyArtifact/instances"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    instances = JSON.parse(last_response.body)

    assert_instance_of Array, instances
  end

  def test_api_instances_404_for_unknown_kind
    get "/api/v1/editor/kinds/UnknownKind/instances"

    assert_equal 404, last_response.status
  end

  def test_api_relation_kinds_returns_valid_kinds
    get "/api/v1/editor/relation-kinds", { "kind" => "TechnologyArtifact", "verb" => "servedBy" }

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    kinds = JSON.parse(last_response.body)

    assert_instance_of Array, kinds
    assert_includes kinds, "TechnologyArtifact"
  end

  def test_api_relation_kinds_400_without_params
    get "/api/v1/editor/relation-kinds"

    assert_equal 400, last_response.status
  end

  # Relations tests

  def test_post_generate_with_relations_includes_spec
    # Find an existing artifact to reference
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    target_instance = artifacts.keys.first

    post "/kinds/TechnologyArtifact/generate", {
      "name" => "test-artifact-with-relations",
      "annotations" => { "artifact/type" => "repo" },
      "relations" => [
        { "verb" => "servedBy", "kind" => "TechnologyArtifact", "name" => target_instance }
      ]
    }

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "Generated YAML"
    assert_includes last_response.body, "spec:"
    assert_includes last_response.body, "servedBy:"
    assert_includes last_response.body, target_instance
  end

  def test_new_form_includes_instances_data_attribute
    get "/kinds/TechnologyArtifact/new"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "data-instances="
  end

  def test_edit_form_relations_use_class_names_not_relation_names
    # Find an instance with relations
    db = Archsight::Web::Application.database
    artifacts = db.instances_by_kind("TechnologyArtifact")
    _, instance = artifacts.find { |_, v| v.spec && !v.spec.empty? }
    skip("No TechnologyArtifact with relations found") unless instance

    get "/kinds/#{instance.kind}/instances/#{instance.name}/edit"

    assert_predicate last_response, :ok?

    # Extract kind values from hidden inputs
    kinds = last_response.body.scan(/name='relations\[\]\[kind\]'\s+value='([^']+)'/).flatten

    # Verify each kind is a class name (PascalCase), not a relation name (camelCase)
    kinds.each do |kind|
      assert_match(/^[A-Z]/, kind, "Kind should be a class name (e.g., BusinessActor), got: #{kind}")
    end
  end

  def test_edit_then_generate_preserves_relations
    # Find an instance with relations
    db = Archsight::Web::Application.database
    artifacts = db.instances_by_kind("TechnologyArtifact")
    _, instance = artifacts.find { |_, v| v.spec && !v.spec.empty? }
    skip("No TechnologyArtifact with relations found") unless instance

    # Load edit page to get relation data
    get "/kinds/#{instance.kind}/instances/#{instance.name}/edit"

    assert_predicate last_response, :ok?

    # Extract relations from hidden inputs
    body = last_response.body
    verbs = body.scan(/name='relations\[\]\[verb\]'\s+value='([^']+)'/).flatten
    kinds = body.scan(/name='relations\[\]\[kind\]'\s+value='([^']+)'/).flatten
    names = body.scan(/name='relations\[\]\[name\]'\s+value='([^']+)'/).flatten

    relations = verbs.zip(kinds, names).map do |verb, kind, name|
      { "verb" => verb, "kind" => kind, "name" => name }
    end

    skip("Instance has no relations in form") if relations.empty?

    # Submit form to generate YAML
    post "/kinds/#{instance.kind}/instances/#{instance.name}/generate", {
      "name_field" => instance.name,
      "relations" => relations
    }

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "spec:", "Generated YAML should include spec with relations"
  end
end
