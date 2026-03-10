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

  # HTML routes serve Vue SPA

  def test_get_new_form_serves_html
    get "/kinds/TechnologyArtifact/new"

    assert_predicate last_response, :ok?, "Expected 200, got #{last_response.status}"
    assert_includes last_response.body, "html"
  end

  def test_get_new_form_404_for_unknown_kind
    get "/kinds/UnknownKind/new"

    assert_equal 404, last_response.status
  end

  def test_get_edit_form_serves_html
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    instance_name = artifacts.keys.first
    get "/kinds/TechnologyArtifact/instances/#{instance_name}/edit"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "html"
  end

  def test_get_edit_form_404_for_unknown_instance
    get "/kinds/TechnologyArtifact/instances/nonexistent-instance-xyz/edit"

    assert_equal 404, last_response.status
  end

  def test_get_edit_form_404_for_unknown_kind
    get "/kinds/UnknownKind/instances/test/edit"

    assert_equal 404, last_response.status
  end

  # API: Form metadata

  def test_api_form_create_returns_metadata
    get "/api/v1/editor/kinds/TechnologyArtifact/form"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = JSON.parse(last_response.body)

    assert_equal "TechnologyArtifact", data["kind"]
    assert_equal "create", data["mode"]
    assert_instance_of Array, data["fields"]
    assert_instance_of Array, data["relation_options"]
    assert_instance_of Hash, data["instances_by_kind"]
    assert data.key?("icon")
    assert data.key?("layer")
    assert data.key?("inline_edit_enabled")
  end

  def test_api_form_create_fields_have_required_keys
    get "/api/v1/editor/kinds/TechnologyArtifact/form"

    data = JSON.parse(last_response.body)
    field = data["fields"].first

    assert field.key?("key")
    assert field.key?("title")
    assert field.key?("input_type")
  end

  def test_api_form_create_404_for_unknown_kind
    get "/api/v1/editor/kinds/UnknownKind/form"

    assert_equal 404, last_response.status
  end

  def test_api_form_edit_returns_instance_values
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    instance_name = artifacts.keys.first
    get "/api/v1/editor/kinds/TechnologyArtifact/instances/#{instance_name}/form"

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = JSON.parse(last_response.body)

    assert_equal "edit", data["mode"]
    assert_equal instance_name, data["name"]
    assert_instance_of Hash, data["annotations"]
    assert_instance_of Array, data["relations"]
    assert data.key?("content_hash")
    assert data.key?("path_ref")
  end

  def test_api_form_edit_404_for_unknown_instance
    get "/api/v1/editor/kinds/TechnologyArtifact/instances/nonexistent-xyz/form"

    assert_equal 404, last_response.status
  end

  # API: Generate YAML

  def test_api_generate_with_valid_data_returns_yaml
    post "/api/v1/editor/kinds/TechnologyArtifact/generate",
         JSON.generate({
                         "name" => "test-artifact",
                         "annotations" => { "artifact/type" => "repo" }
                       }),
         { "CONTENT_TYPE" => "application/json" }

    assert_predicate last_response, :ok?
    assert_includes last_response.content_type, "application/json"

    data = JSON.parse(last_response.body)

    assert_includes data["yaml"], "test-artifact"
    assert_includes data["yaml"], "apiVersion"
    assert_nil data["errors"]
  end

  def test_api_generate_with_invalid_name_returns_errors
    post "/api/v1/editor/kinds/TechnologyArtifact/generate",
         JSON.generate({ "name" => "", "annotations" => {} }),
         { "CONTENT_TYPE" => "application/json" }

    assert_predicate last_response, :ok?

    data = JSON.parse(last_response.body)

    assert_nil data["yaml"]
    assert_instance_of Hash, data["errors"]
    assert data["errors"].key?("name")
  end

  def test_api_generate_with_spaces_in_name_returns_errors
    post "/api/v1/editor/kinds/TechnologyArtifact/generate",
         JSON.generate({ "name" => "test artifact", "annotations" => {} }),
         { "CONTENT_TYPE" => "application/json" }

    assert_predicate last_response, :ok?

    data = JSON.parse(last_response.body)

    assert_nil data["yaml"]
    assert data["errors"]["name"]
  end

  def test_api_generate_with_invalid_enum_returns_errors
    post "/api/v1/editor/kinds/TechnologyArtifact/generate",
         JSON.generate({
                         "name" => "test-artifact",
                         "annotations" => { "artifact/type" => "invalid_value" }
                       }),
         { "CONTENT_TYPE" => "application/json" }

    assert_predicate last_response, :ok?

    data = JSON.parse(last_response.body)

    assert_nil data["yaml"]
    assert data["errors"].key?("artifact/type")
  end

  def test_api_generate_with_relations_includes_spec
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    target_instance = artifacts.keys.first

    post "/api/v1/editor/kinds/TechnologyArtifact/generate",
         JSON.generate({
                         "name" => "test-artifact-with-relations",
                         "annotations" => { "artifact/type" => "repo" },
                         "relations" => [
                           { "verb" => "servedBy", "kind" => "TechnologyArtifact", "names" => [target_instance] }
                         ]
                       }),
         { "CONTENT_TYPE" => "application/json" }

    assert_predicate last_response, :ok?

    data = JSON.parse(last_response.body)

    assert_includes data["yaml"], "spec:"
    assert_includes data["yaml"], "servedBy:"
    assert_includes data["yaml"], target_instance
  end

  def test_api_generate_404_for_unknown_kind
    post "/api/v1/editor/kinds/UnknownKind/generate",
         JSON.generate({ "name" => "test" }),
         { "CONTENT_TYPE" => "application/json" }

    assert_equal 404, last_response.status
  end

  def test_api_generate_400_for_invalid_json
    post "/api/v1/editor/kinds/TechnologyArtifact/generate",
         "not json",
         { "CONTENT_TYPE" => "application/json" }

    assert_equal 400, last_response.status
  end

  # API: Edit generate

  def test_api_edit_generate_with_valid_data_returns_yaml
    artifacts = Archsight::Web::Application.database.instances_by_kind("TechnologyArtifact")
    skip("No TechnologyArtifact instances") if artifacts.empty?

    instance_name = artifacts.keys.first

    post "/api/v1/editor/kinds/TechnologyArtifact/instances/#{instance_name}/generate",
         JSON.generate({
                         "name" => "updated-artifact",
                         "annotations" => { "artifact/type" => "repo" }
                       }),
         { "CONTENT_TYPE" => "application/json" }

    assert_predicate last_response, :ok?

    data = JSON.parse(last_response.body)

    assert_includes data["yaml"], "updated-artifact"
    assert_nil data["errors"]
    assert data.key?("path_ref")
  end

  # Existing API endpoints

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
end
