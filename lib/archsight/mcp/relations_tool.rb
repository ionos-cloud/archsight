# frozen_string_literal: true

require_relative "base"

class Archsight::MCP::RelationsTool < FastMcp::Tool
  tool_name "relations"

  description <<~DESC.gsub("\n", " ").strip
    List the DIRECT relations of one resource, filtered and grouped by verb. No transitive expansion, no other
    resource details (use analyze_resource for those, or depth/impact for transitive views).

    Each relation is {verb, direction, kind, name}: direction 'out' = this resource points at the target
    (e.g. realizedThrough), 'in' = the other resource points at this one (e.g. what it is servedBy).

    EXAMPLES:
    kind="ApplicationService", name="X", verb="realizedThrough" - only the direct realizedThrough targets
    kind="ApplicationComponent", name="Y", direction="in", target_kind="ApplicationService" - which services use Y

    A name that does not exist returns the closest matches across all kinds.

    TYPICAL FLOW: find the exact name with query (output='brief'), then ask for one verb or one target kind here.
    PITFALLS: kind and name are exact and case-sensitive; verbs are exact (a verb the resource does not have
    gives a warning listing the verbs it has); 'in' relations are the ones other resources declare towards it.
  DESC
  arguments do
    required(:kind).filled(:string).description("Resource kind, e.g. ApplicationService")
    required(:name).filled(:string).description(
      "Exact name of the resource (case-sensitive). A wrong name returns suggestions."
    )
    optional(:verb).filled(:string).description("Only this relation verb (e.g. 'realizedThrough', 'servedBy')")
    optional(:direction).filled(:string).description(
      "'out' (this resource points at the target), 'in' (the other points at this one), 'both' (default)"
    )
    optional(:target_kind).filled(:string).description("Only relations whose other end is of this kind")
    optional(:limit).filled(:integer).description("Maximum relations returned (default 100, max 500)")
  end

  DIRECTIONS = %w[out in both].freeze

  def call(kind:, name:, verb: nil, direction: "both", target_kind: nil, limit: 100)
    return error("Unknown resource kind: #{kind}") unless Archsight::Resources[kind]
    return error("Unknown direction: #{direction}. Use out, in or both") unless DIRECTIONS.include?(direction)

    instance = Archsight::MCP.db.instance_by_kind(kind, name)
    return not_found(kind, name) unless instance

    build(instance, kind, name, verb, direction, target_kind, [[limit.to_i, 1].max, 500].min)
  rescue StandardError => e
    error("#{e.class}: #{e.message}")
  end

  private

  def build(instance, kind, name, verb, direction, target_kind, limit)
    all = Archsight::MCP.direct_relations(instance)
    relations = all.select do |rel|
      (verb.nil? || rel[:verb] == verb) &&
        (direction == "both" || rel[:direction] == direction) &&
        (target_kind.nil? || rel[:kind] == target_kind)
    end
    relations = relations.sort_by { |rel| [rel[:verb], rel[:direction], rel[:kind], rel[:name]] }
    shown = relations.first(limit)

    result = { resource: { kind: kind, name: name }, total: relations.length, shown: shown.length }
    result[:by_verb] = relations.group_by { |rel| rel[:verb] }.transform_values(&:length)
    result[:relations] = shown.group_by { |rel| rel[:verb] }
    result[:truncated] = "#{relations.length - shown.length} more not listed; narrow with verb, direction or target_kind" if shown.length < relations.length
    warning = unknown_verb_warning(all, verb)
    result[:warning] = warning if warning && relations.empty?
    JSON.pretty_generate(result)
  end

  def unknown_verb_warning(all, verb)
    return nil if verb.nil? || all.any? { |rel| rel[:verb] == verb }

    known = all.map { |rel| rel[:verb] }.uniq.sort
    "This resource has no relations with verb \"#{verb}\". Verbs present: #{known.empty? ? "none" : known.join(", ")}"
  end

  def not_found(kind, name)
    suggestions = Archsight::MCP.suggest(name, kind: kind)
    message = ["Resource not found: #{kind}/#{name}", Archsight::MCP.did_you_mean(suggestions)].compact.join(". ")
    JSON.pretty_generate({ error: "Error", message: message, suggestions: suggestions })
  end

  def error(message)
    JSON.pretty_generate({ error: "Error", message: message })
  end
end
