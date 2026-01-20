# frozen_string_literal: true

require "sinatra/base"
require "sinatra/extension"
require_relative "json_helpers"

module Archsight; end
module Archsight::Web; end
module Archsight::Web::API; end

# REST API routes for Archsight
module Archsight::Web::API::Routes
  extend Sinatra::Extension

  helpers Archsight::Web::API::JsonHelpers

  # GET /api/v1/kinds - List all resource kinds with counts
  get "/api/v1/kinds" do
    kinds = build_kinds_list
    total = kinds.sum { |k| k[:instance_count] }

    json_response(
      { total: kinds.length, total_instances: total, kinds: kinds }
    )
  end

  # GET /api/v1/kinds/:kind - List instances of a kind (paginated)
  get "/api/v1/kinds/:kind" do
    kind = params[:kind]
    klass = Archsight::Resources[kind]
    json_error("Kind '#{kind}' not found", status: 404, error_type: "NotFound") unless klass

    instances = db.instances_by_kind(kind).values.sort_by(&:name)
    limit, offset = parse_pagination_params
    output = parse_output_param
    pagination = paginate(instances, limit: limit, offset: offset)

    resources = pagination[:items].map do |inst|
      resource_summary(inst, output: output, omit_kind: true)
    end

    json_response(build_list_response(kind, pagination, resources))
  end

  # GET /api/v1/kinds/:kind/instances/:name - Get instance details with relations
  get "/api/v1/kinds/:kind/instances/:name" do
    kind = params[:kind]
    name = params[:name]

    klass = Archsight::Resources[kind]
    json_error("Kind '#{kind}' not found", status: 404, error_type: "NotFound") unless klass

    instance = db.instance_by_kind(kind, name)
    json_error("Instance '#{name}' not found", status: 404, error_type: "NotFound") unless instance

    json_response(build_instance_response(kind, instance))
  end

  # GET /api/v1/search - Search with query language
  get "/api/v1/search" do
    query = params[:q]
    json_error("Query parameter 'q' is required", status: 400, error_type: "BadRequest") unless query

    start_time = Time.now

    begin
      parsed_query = Archsight::Query.parse(query)
      results = parsed_query.filter(db)
      query_time_ms = ((Time.now - start_time) * 1000).round(2)
      output = parse_output_param

      if output == "count"
        json_response(build_count_response(query, results, query_time_ms))
      else
        json_response(build_search_response(query, results, parsed_query, query_time_ms))
      end
    rescue Archsight::Query::QueryError => e
      json_error(e.message, status: 400, error_type: "QueryError", query: query)
    end
  end

  # GET /api/v1/openapi.yaml - OpenAPI specification
  get "/api/v1/openapi.yaml" do
    content_type "text/yaml"
    spec_path = File.join(__dir__, "openapi", "spec.yaml")
    File.read(spec_path)
  end

  # Convenience aliases with .json suffix
  get "/kinds.json" do
    call env.merge("PATH_INFO" => "/api/v1/kinds")
  end

  get "/kinds/:kind.json" do
    call env.merge("PATH_INFO" => "/api/v1/kinds/#{params[:kind]}")
  end

  get "/kinds/:kind/instances/:name.json" do
    call env.merge("PATH_INFO" => "/api/v1/kinds/#{params[:kind]}/instances/#{params[:name]}")
  end
end
