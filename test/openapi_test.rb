# frozen_string_literal: true

require "test_helper"
require "rack/test"
require "json"
require "json_schemer"
require "archsight/openapi"
require "archsight/web/application"

# The OpenAPI document is the hand-written base plus what Archsight::OpenAPI generates from the model: these tests keep
# the two and the real responses from drifting apart.
class OpenAPITest < Minitest::Test
  include Rack::Test::Methods

  def app = Archsight::Web::Application

  def setup
    Archsight.resources_dir = File.expand_path("../examples/archsight", __dir__)
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
    @document = Archsight::OpenAPI.document
    @schemer = JSONSchemer.openapi(@document)
  end

  def kinds = Archsight::Resources.resource_classes.keys.sort

  def test_the_document_is_valid_openapi
    errors = @schemer.validate.map { |error| "#{error["data_pointer"]}: #{error["error"]}" }

    assert_empty errors.first(10)
  end

  def test_the_served_document_is_the_generated_one
    get "/api/v1/openapi.yaml"

    assert_equal @document, YAML.safe_load(last_response.body)
  end

  def test_every_reference_resolves
    missing = refs(@document).uniq.reject { |ref| resolve(ref) }

    assert_empty missing
  end

  def test_nothing_uses_the_openapi_3_0_nullable
    refute_includes YAML.dump(@document), "nullable"
  end

  def test_every_kind_has_a_schema_and_is_a_kind_name
    schemas = @document.dig("components", "schemas")

    assert_equal kinds, schemas.dig("KindName", "enum")
    kinds.each { |kind| assert schemas.key?(Archsight::OpenAPI.schema_name(kind)), "no schema for #{kind}" }
    assert_equal kinds, schemas.dig("InstanceDetail", "discriminator", "mapping").keys
  end

  def test_the_annotations_of_a_schema_are_the_ones_of_the_kind
    kinds.each do |kind|
      klass = Archsight::Resources[kind]
      annotations = @document.dig("components", "schemas", Archsight::OpenAPI.schema_name(kind), "properties", "metadata", "properties", "annotations")

      assert_equal klass.annotations.reject(&:pattern?).map(&:key).sort, annotations["properties"].keys.sort, kind
      klass.annotations.select(&:enum).reject(&:pattern?).each do |annotation|
        key = annotation.list? ? "x-items-enum" : "enum" # a list holds several values, each one of the enum

        assert_equal annotation.enum, annotations.dig("properties", annotation.key, key), "#{kind} #{annotation.key}"
      end
    end
  end

  def test_the_relations_of_a_schema_are_the_ones_of_the_kind
    kinds.each do |kind|
      schema = @document.dig("components", "schemas", Archsight::OpenAPI.schema_name(kind), "properties")
      klass = Archsight::Resources[kind]

      assert_equal klass.declared_relations.map { |verb, _, _| verb.to_s }.uniq.sort, schema.dig("spec", "properties").keys.sort, kind
      assert_equal klass.relations.map { |verb, _, _| verb.to_s }.uniq.sort, schema.dig("relations", "properties").keys.sort, kind
    end
  end

  def test_a_new_annotation_and_relation_reach_the_schema
    klass = Class.new(Archsight::Resources::Base) do
      def self.name = "Archsight::Resources::ProbeKind"
      annotation "probe/level", description: "How deep", type: Integer, enum: %w[1 2]
      relation :dependsOn, :applicationComponents, :ApplicationComponent
    end
    Archsight::Resources.register(klass)
    Archsight::OpenAPI.reset!
    schema = Archsight::OpenAPI.document.dig("components", "schemas", "ProbeKindInstance", "properties")

    assert_equal({ "type" => %w[integer string], "description" => "How deep", "enum" => %w[1 2] }, schema.dig("metadata", "properties", "annotations", "properties", "probe/level"))
    assert_equal ["applicationComponents"], schema.dig("spec", "properties", "dependsOn", "properties").keys
  ensure
    Archsight::Resources.resource_classes.delete("ProbeKind")
    Archsight::OpenAPI.reset!
  end

  # The strongest guard: the JSON the API really answers with is what the schema of the kind says
  def test_every_instance_response_matches_the_schema_of_its_kind
    checked = 0
    kinds.each do |kind|
      Archsight::Web::Application.database.instances_by_kind(kind).each_key do |name|
        get "/api/v1/kinds/#{kind}/instances/#{ERB::Util.url_encode(name)}"

        assert_predicate last_response, :ok?, "#{kind}/#{name}"
        data = JSON.parse(last_response.body)
        errors = @schemer.ref("#/components/schemas/#{Archsight::OpenAPI.schema_name(kind)}").validate(data).map { |e| "#{e["data_pointer"]}: #{e["error"]}" }

        assert_empty errors.first(5), "#{kind}/#{name}"
        checked += 1
      end
    end

    assert_operator checked, :>, 20
  end

  # Pages of the browser (the single page app and its redirects) are not part of the API
  BROWSER_ROUTES = %w[/doc/:filename /doc/resources/:filename /docs/api /kinds/:kind /kinds/:kind/generate /kinds/:kind/new
                      /kinds/:kind/instances/:instance /kinds/:kind/instances/:name/edit /kinds/:kind/instances/:name/generate].freeze

  def test_every_api_route_is_documented
    documented = @document["paths"].keys.map { |path| normalize(path) }
    routes = app.routes.values_at("GET", "POST").flatten(1).map { |pattern, *| pattern.to_s }.uniq
    api = routes.select { |route| route.start_with?("/api/v1", "/kinds", "/dot", "/reload", "/maintenance") } - BROWSER_ROUTES

    assert_empty api.reject { |route| documented.include?(normalize(route)) }.sort
  end

  private

  # /kinds/:kind/instances/{name} -> /kinds/:/instances/:  (parameter names differ between Sinatra and OpenAPI)
  def normalize(path) = path.gsub(/\{[^}]+\}|:\w+|\*/, ":").sub(%r{/\z}, "")

  def refs(node)
    case node
    when Hash then node.flat_map { |key, value| key == "$ref" && value.is_a?(String) ? [value] : refs(value) }
    when Array then node.flat_map { |value| refs(value) }
    else []
    end
  end

  def resolve(ref)
    ref.delete_prefix("#/").split("/").reduce(@document) { |node, key| node.is_a?(Hash) ? node[key.gsub("~1", "/").gsub("~0", "~")] : nil }
  end
end
