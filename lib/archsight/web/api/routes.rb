# frozen_string_literal: true

require "sinatra/base"
require "sinatra/extension"
require_relative "json_helpers"
require_relative "page_helpers"
require_relative "../../assets"

module Archsight; end
module Archsight::Web; end
module Archsight::Web::API; end

# REST API routes for Archsight
module Archsight::Web::API::Routes
  extend Sinatra::Extension

  helpers Archsight::Web::API::JsonHelpers
  helpers Archsight::Web::API::PageHelpers

  # Rendering is CPU work, previews are typed, not pasted
  MAX_DIAGRAM_SOURCE = 100_000

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

  # GET /api/v1/kinds/:kind/filters - Get filterable annotations with values
  get "/api/v1/kinds/:kind/filters" do
    kind = params[:kind]
    klass = Archsight::Resources[kind]
    json_error("Kind '#{kind}' not found", status: 404, error_type: "NotFound") unless klass

    json_response(build_filters_response(kind))
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

  # GET /api/v1/pages - Page tree built from PageMenu resources, page tags and the home page
  # (shown at `/`; it is not in the tree unless a menu contains it)
  get "/api/v1/pages" do
    tree = Archsight::PageTree.new(db)
    home = tree.home_page
    json_response({ pages: tree.tree, tags: page_tag_counts, home: home && { name: home.name, title: home.title } })
  end

  # GET /api/v1/pages/:name - Rendered page with metadata, toc, breadcrumb and backlinks
  get "/api/v1/pages/:name" do
    page = db.instance_by_kind("Page", params[:name])
    json_error("Page '#{params[:name]}' not found", status: 404, error_type: "NotFound") unless page

    json_response(build_page_response(page))
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

  # GET /api/v1/assets/*path - Images and draw.io diagrams that markdown embeds. The path is relative to the
  # resources directory; only files of the allowed types inside it are ever served, never anything outside of
  # it and never resource definitions (see Archsight::Assets). Outside, missing and not-served-type all
  # answer the same 404.
  get "/api/v1/assets/*" do
    file = Archsight::Assets.file_for(params["splat"].first, resources_dir: Archsight.resources_dir)
    json_error("Asset not found", status: 404, error_type: "NotFound") unless file
    json_error("Asset is too large", status: 413, error_type: "PayloadTooLarge") if File.size(file) > Archsight::Assets::MAX_BYTES

    type = Archsight::Assets.content_type(file)
    headers "X-Content-Type-Options" => "nosniff"
    return serve_diagram_asset(file) if Archsight::Assets.asd?(file)

    # an SVG opened directly (not as <img>) must not be able to run script
    headers "Content-Security-Policy" => "default-src 'none'; style-src 'unsafe-inline'; sandbox" if type == "image/svg+xml"
    cache_control :public, :must_revalidate, max_age: 0
    etag "#{File.mtime(file).to_i}-#{File.size(file)}"
    send_file file, type: type, disposition: :inline
  end

  helpers do
    # An .asd asset is served as what it stands for, the rendered SVG, not as its source. The ETag is the
    # fingerprint of the source and of how its `resource` links resolve, so clients and the server's render
    # cache keep it for as long as neither the file nor the linked resources changed.
    def serve_diagram_asset(file)
      source = File.read(file, encoding: "UTF-8")
      resolver = Archsight::Helpers::ResourceResolver.new(db)
      headers "Content-Security-Policy" => "default-src 'none'; style-src 'unsafe-inline'; sandbox"
      cache_control :public, :must_revalidate, max_age: 0
      etag Archsight::Helpers::DiagramBlocks.fingerprint(source, resolver: resolver)
      content_type "image/svg+xml"
      Archsight::Helpers::DiagramBlocks.standalone_svg(source, resolver: resolver)
    rescue Archsight::Diagram::Error => e
      json_error("Diagram does not render: #{e.message}", status: 422, error_type: "DiagramError")
    end
  end

  # POST /api/v1/diagrams/render - Render .asd source for the editor preview. A diagram that does not
  # parse is a normal outcome while typing, so it is a 200 with `error` set.
  post "/api/v1/diagrams/render" do
    body = request.body.read(MAX_DIAGRAM_SOURCE + 1).to_s
    json_error("Diagram source is too large", status: 413, error_type: "PayloadTooLarge") if body.bytesize > MAX_DIAGRAM_SOURCE

    source = begin
      JSON.parse(body)["source"]
    rescue JSON::ParserError, TypeError
      nil
    end
    json_error("A JSON body with a 'source' string is required", status: 400, error_type: "BadRequest") unless source.is_a?(String)

    resolver = Archsight::Helpers::ResourceResolver.new(db)
    json_response(Archsight::Helpers::DiagramBlocks.preview(source, resolver: resolver))
  end

  # POST /api/v1/kinds/Analysis/instances/:name/execute - Execute an analysis
  post "/api/v1/kinds/Analysis/instances/:name/execute" do
    require "archsight/analysis"

    name = params[:name]
    analysis = db.instance_by_kind("Analysis", name)
    json_error("Analysis '#{name}' not found", status: 404, error_type: "NotFound") unless analysis

    executor = Archsight::Analysis::Executor.new(db)
    result = executor.execute(analysis)

    json_response(build_analysis_result(result))
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
