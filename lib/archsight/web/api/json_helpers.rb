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
    result = case output
             when "brief"
               Archsight::MCP.brief_summary(resource, omit_kind: omit_kind)
             when "annotations"
               Archsight::MCP.annotations_summary(resource, omit_kind: omit_kind)
             else # "complete"
               summary = Archsight::MCP.complete_summary(resource, omit_kind: omit_kind)
               summary[:spec] = serialize_spec(summary[:spec]) if summary[:spec]
               summary
             end
    result[:icon] = resource.class.icon
    result[:layer] = resource.class.layer
    result
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

  MARKDOWN_ANNOTATION_KEYS = Set["architecture/description"].freeze

  def build_instance_response(kind, instance)
    {
      kind: kind,
      name: instance.name,
      metadata: { annotations: render_annotations(instance.annotations) },
      spec: serialize_spec(instance.spec),
      relations: extract_relations(instance),
      references: extract_references(instance)
    }
  end

  def render_annotations(annotations)
    annotations.each_with_object({}) do |(key, value), result|
      result[key] = if MARKDOWN_ANNOTATION_KEYS.include?(key) && value.is_a?(String)
                      markdown(value)
                    else
                      value
                    end
    end
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

  def build_search_response(query, results, _parsed_query, query_time_ms)
    limit, offset = parse_pagination_params
    output = parse_output_param
    sorted = results.sort_by(&:name)
    pagination = paginate(sorted, limit: limit, offset: offset)

    instances = pagination[:items].map do |r|
      resource_summary(r, output: output, omit_kind: false)
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

    instance.class.relations.each do |verb, spec_key, kind|
      rels = instance.relations(verb, spec_key).map(&:name)
      next if rels.empty?

      relations[verb] ||= {}
      relations[verb][kind] = rels
    end

    relations
  end

  def build_filters_response(kind)
    db.filters_for_kind(kind).map do |annotation, values|
      {
        key: annotation.key,
        title: annotation.title,
        description: annotation.description,
        filter_type: annotation.filter.to_s,
        values: values
      }
    end
  end

  def build_analysis_result(result)
    data = {
      name: result.name,
      success: result.success?,
      has_findings: result.has_findings?,
      duration: result.duration,
      sections: result.sections.map { |s| serialize_analysis_section(s) }
    }

    if result.failed?
      data[:error] = result.error
      data[:error_backtrace] = result.error_backtrace if result.error_backtrace&.any?
    end

    data
  end

  def serialize_analysis_section(section)
    case section[:type]
    when :heading
      { type: "heading", level: section[:level], text: section[:text] }
    when :text
      { type: "text", content: section[:content] }
    when :message
      { type: "message", level: section[:level].to_s, message: section[:message] }
    when :table
      { type: "table", headers: section[:headers], rows: section[:rows] }
    when :list
      { type: "list", items: section[:items] }
    when :code
      { type: "code", lang: section[:lang], content: section[:content] }
    else
      { type: section[:type].to_s }
    end
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
