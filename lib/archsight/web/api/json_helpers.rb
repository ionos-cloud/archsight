# frozen_string_literal: true

module Archsight; end
module Archsight::Web; end
module Archsight::Web::API; end

# Shared helpers for JSON API responses
module Archsight::Web::API::JsonHelpers
  DEFAULT_LIMIT = 50
  MAX_LIMIT = 500

  def json_response(data, status: 200)
    content_type :json
    halt status, JSON.pretty_generate(data)
  end

  def json_error(message, status:, error_type: "Error", query: nil)
    content_type :json
    error = { error: error_type, message: message }
    error[:query] = query if query
    halt status, JSON.pretty_generate(error)
  end

  def resource_summary(resource, output:, omit_kind: false)
    case output
    when "brief"
      Archsight::MCP.brief_summary(resource, omit_kind: omit_kind)
    else # "complete"
      Archsight::MCP.complete_summary(resource, omit_kind: omit_kind)
    end
  end

  def paginate(collection, limit:, offset:)
    limit = [[limit.to_i, 1].max, MAX_LIMIT].min
    offset = [offset.to_i, 0].max
    {
      items: collection.drop(offset).take(limit),
      limit: limit,
      offset: offset,
      total: collection.length
    }
  end

  def parse_pagination_params
    limit = (params[:limit] || DEFAULT_LIMIT).to_i
    offset = (params[:offset] || 0).to_i
    [limit, offset]
  end

  def parse_output_param
    params[:output] || "complete"
  end

  def build_kinds_list
    kinds = Archsight::Resources.resource_classes.map do |kind_name, klass|
      count = db.instances_by_kind(kind_name).length
      {
        kind: kind_name,
        description: klass.description,
        layer: klass.layer,
        icon: klass.icon,
        instance_count: count
      }
    end
    kinds.sort_by { |k| k[:kind] }
  end

  def build_list_response(kind, pagination, instances)
    {
      kind: kind,
      total: pagination[:total],
      limit: pagination[:limit],
      offset: pagination[:offset],
      count: instances.length,
      instances: instances
    }
  end

  def build_instance_response(kind, instance)
    {
      kind: kind,
      name: instance.name,
      metadata: { annotations: instance.annotations },
      spec: serialize_spec(instance.spec),
      relations: extract_relations(instance),
      references: extract_references(instance)
    }
  end

  def serialize_spec(spec)
    spec.transform_values do |kinds|
      next kinds unless kinds.is_a?(Hash)

      kinds.transform_values do |instances|
        next instances unless instances.is_a?(Array)

        instances.map { |i| i.is_a?(Archsight::Resources::Base) ? i.name : i }
      end
    end
  end

  def build_count_response(query, results, query_time_ms)
    by_kind = results.group_by { |r| r.class.to_s.split("::").last }
                     .transform_values(&:length)
    {
      query: query,
      total: results.length,
      query_time_ms: query_time_ms,
      by_kind: by_kind
    }
  end

  def build_search_response(query, results, parsed_query, query_time_ms)
    limit, offset = parse_pagination_params
    output = parse_output_param
    omit_kind = !parsed_query.kind_filter.nil?
    sorted = results.sort_by(&:name)
    pagination = paginate(sorted, limit: limit, offset: offset)

    instances = pagination[:items].map do |r|
      resource_summary(r, output: output, omit_kind: omit_kind)
    end

    {
      query: query,
      total: pagination[:total],
      limit: pagination[:limit],
      offset: pagination[:offset],
      count: instances.length,
      query_time_ms: query_time_ms,
      instances: instances
    }
  end

  def extract_relations(instance)
    relations = {}

    instance.class.relations.each do |verb, kind_name, _|
      rels = instance.relations(verb, kind_name).map(&:name)
      next if rels.empty?

      relations[verb] ||= {}
      relations[verb][kind_name] = rels
    end

    relations
  end

  def extract_references(instance)
    references = {}

    instance.references.each do |ref|
      inst = ref[:instance]
      verb = ref[:verb]
      kind = inst.klass

      references[kind] ||= {}
      references[kind][verb] ||= []
      references[kind][verb] << inst.name
    end

    references
  end
end
