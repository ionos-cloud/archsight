# frozen_string_literal: true

require_relative "base"

class Archsight::MCP::AnalyzeResourceTool < FastMcp::Tool
  tool_name "analyze_resource"

  description <<~DESC.gsub("\n", " ").strip
    Get detailed information about a specific architecture resource by kind and name.

    THREE MODES OF OPERATION:

    1. BASIC MODE (default): Returns resource details including spec, annotations, and direct relations.
       Example: kind="ApplicationComponent", name="MyService"

    2. DEPENDENCY TREE MODE (depth > 0): Returns hierarchical view of all dependencies.
       Shows both outgoing (what this resource depends on) and incoming (what depends on this resource)
       relations recursively up to the specified depth.
       Example: kind="ApplicationComponent", name="MyService", depth=3

    3. IMPACT ANALYSIS MODE (impact=true): Analyzes what would break if this resource is deprecated.
       Returns all resources that directly or transitively depend on this resource, grouped by
       kind/verb/depth with summary statistics. Essential for change impact assessment.
       Example: kind="ApplicationInterface", name="Kubernetes:RestAPI", impact=true

    RESOURCE KINDS: TechnologyArtifact, ApplicationComponent, ApplicationInterface,
    ApplicationService, MotivationRequirement, ComplianceEvidence, and more.
  DESC
  arguments do
    required(:kind).filled(:string).description(
      "Resource type to analyze. Common kinds: TechnologyArtifact (repos, code), " \
      "ApplicationComponent (services), ApplicationInterface (APIs), " \
      "MotivationRequirement (compliance and legal requirements), ComplianceEvidence (compliance proof)"
    )
    required(:name).filled(:string).description(
      "Exact name of the resource (case-sensitive). Use QueryTool first if unsure of exact name."
    )
    optional(:depth).filled(:integer).description(
      "Dependency tree depth (0-10). " \
      "0 = show direct relations only (default), " \
      "1+ = recursively expand dependencies to this depth. " \
      "Higher values show more context but increase response size."
    )
    optional(:impact).filled(:bool).description(
      "Enable impact analysis mode. When true, finds all resources that would be affected " \
      "if this resource is deprecated or removed. Returns grouped results with statistics. " \
      "Useful for change management and deprecation planning."
    )
    optional(:kinds).array(:string).description(
      "Impact mode: only follow and report these kinds (e.g. ['ApplicationComponent']). Default: all kinds."
    )
    optional(:exclude_kinds).array(:string).description(
      "Impact mode: skip these kinds and do not follow through them (e.g. ['Page', 'PageMenu'])."
    )
    optional(:verbs).array(:string).description(
      "Impact mode: only follow these relation verbs (e.g. ['realizedThrough', 'servedBy'])."
    )
    optional(:direction).filled(:string).description(
      "Impact mode: 'in' = what depends on this resource (default), 'out' = what this resource depends on."
    )
    optional(:limit).filled(:integer).description(
      "Impact mode: maximum entries listed (nearest first). The summary (counts by kind) always covers all of " \
      "them and says how many were left out."
    )
    optional(:group_by).filled(:string).description(
      "How to group impact analysis results: " \
      "'kind' = group by resource type (default, good for understanding scope), " \
      "'verb' = group by relationship type (exposes, realizes, etc.), " \
      "'depth' = group by distance from target (1=direct, 2+=transitive)"
    )
  end

  def call(kind:, name:, depth: 0, impact: false, group_by: "kind", kinds: nil, exclude_kinds: nil, verbs: nil,
           direction: "in", limit: nil)
    db = Archsight::MCP.db

    klass = Archsight::Resources[kind]
    return error_response("Unknown resource kind: #{kind}") unless klass

    instance = db.instance_by_kind(kind, name)
    return not_found_response(kind, name) unless instance

    depth = [[depth.to_i, 0].max, 10].min # Clamp to 0-10

    if impact
      filter = { kinds: kinds, exclude_kinds: exclude_kinds, verbs: verbs&.map(&:to_s), direction: direction.to_s }
      build_impact_analysis(db, instance, kind, name, depth, group_by, filter, limit)
    else
      build_resource_analysis(db, instance, kind, name, depth)
    end
  rescue StandardError => e
    error_response(e.message, e.class.name, e.backtrace&.first(10))
  end

  private

  # Not found: the closest names across all kinds, so a typo or a wrong kind is one call away from the answer
  def not_found_response(kind, name)
    suggestions = Archsight::MCP.suggest(name, kind: kind)
    message = ["Resource not found: #{kind}/#{name}", Archsight::MCP.did_you_mean(suggestions)].compact.join(". ")
    JSON.pretty_generate({ error: "Error", message: message, suggestions: suggestions })
  end

  def error_response(message, error_type = "Error", backtrace = nil)
    result = {
      error: error_type,
      message: message
    }
    result[:backtrace] = backtrace if backtrace
    JSON.pretty_generate(result)
  end

  def build_resource_analysis(db, instance, kind, name, depth)
    result = {
      kind: kind,
      name: name,
      spec: instance.spec,
      annotations: instance.annotations
    }.merge(Archsight::MCP.source_info(instance))

    if depth.positive?
      # Include dependency trees
      visited = Set.new
      result[:outgoing] = build_dependency_tree(db, instance, "outgoing", 0, depth, visited.dup)
      result[:incoming] = build_dependency_tree(db, instance, "incoming", 0, depth, visited.dup)
    else
      # Just direct relations
      result[:relations] = Archsight::MCP.extract_relations(instance)
      result[:related] = Archsight::MCP.related_sources(instance)
      result[:has_relations] = instance.has_relations?
    end

    JSON.pretty_generate(result)
  end

  def build_impact_analysis(db, instance, kind, name, max_depth, group_by, filter, limit)
    max_depth = 5 if max_depth.zero? # Default depth for impact analysis
    limit = [limit.to_i, 1].max if limit

    impacted = []
    edges = ImpactEdges.new(db, filter)
    collect_impact(edges, instance, 0, max_depth, Set.new, impacted)

    # Summary statistics always cover everything found, whatever is listed
    summary = {
      total_impacted: impacted.length,
      unique_resources: impacted.map { |i| "#{i[:kind]}/#{i[:name]}" }.uniq.length,
      by_kind: impacted.group_by { |i| i[:kind] }.transform_values(&:length),
      max_depth_reached: impacted.map { |i| i[:depth] }.max || 0
    }

    result = {
      target: { kind: kind, name: name },
      analysis: "impact",
      direction: filter[:direction],
      max_depth: max_depth,
      group_by: group_by,
      summary: summary
    }
    result[:filters] = filter.slice(:kinds, :exclude_kinds, :verbs).compact unless filter.slice(:kinds, :exclude_kinds, :verbs).compact.empty?

    ordered = impacted.each_with_index.sort_by { |entry, index| [entry[:depth], index] }.map(&:first)
    shown = limit ? ordered.take(limit) : ordered
    result[:impacted_resources] = group_impacted(shown, group_by)

    Archsight::MCP.fit(truncation_note(result, impacted.length, shown.length)) do |attempt|
      keep = [shown.length / (2**attempt), 1].max
      result[:impacted_resources] = group_impacted(ordered.take(keep), group_by)
      truncation_note(result, impacted.length, keep, budget: true)
    end
  end

  def group_impacted(entries, group_by)
    case group_by
    when "verb" then entries.group_by { |i| i[:verb].to_s }
    when "kind" then entries.group_by { |i| i[:kind] }
    when "depth" then entries.group_by { |i| i[:depth] }
    else { "all" => entries }
    end
  end

  # Says how many entries are left out and how to narrow the request
  def truncation_note(result, total, shown, budget: false)
    return result if shown >= total

    reason = budget ? "size budget" : "limit"
    result.merge(
      truncated: "#{total - shown} more entries not listed (#{reason}); #{shown} of #{total} shown, nearest first. " \
                 "Narrow with exclude_kinds, kinds, verbs, a smaller depth or direction."
    )
  end

  # The relations to follow from a resource, filtered by kind and verb. `in` finds the resources that point at it
  # (via an index over all relations, built once), `out` the ones it points at.
  class ImpactEdges
    def initialize(db, filter)
      @db = db
      @filter = filter
      @incoming = nil
    end

    # [[resource, verb], ...]
    def next_from(resource)
      pairs = @filter[:direction] == "out" ? outgoing(resource) : incoming(resource)
      pairs.select { |other, verb| allowed?(other, verb) }
    end

    private

    def allowed?(other, verb)
      kind = other.class.to_s.split("::").last
      return false if @filter[:kinds] && !@filter[:kinds].empty? && !@filter[:kinds].include?(kind)
      return false if @filter[:exclude_kinds]&.include?(kind)

      @filter[:verbs].nil? || @filter[:verbs].empty? || @filter[:verbs].include?(verb.to_s)
    end

    def outgoing(resource)
      resource.class.relations.flat_map do |verb, kind_name, _|
        resource.relations(verb, kind_name).map { |target| [target, verb] }
      end
    end

    def incoming(resource)
      build_index unless @incoming
      @incoming[resource] || []
    end

    def build_index
      @incoming = {}
      @db.instances.each_value do |instances_hash|
        instances_hash.each_value do |other|
          other.class.relations.each do |verb, kind_name, _|
            other.relations(verb, kind_name).each do |target|
              next if target == other

              (@incoming[target] ||= []) << [other, verb]
            end
          end
        end
      end
    end
  end

  def collect_impact(edges, resource, current_depth, max_depth, visited, collector)
    return if current_depth >= max_depth

    key = "#{resource.class.to_s.split("::").last}/#{resource.name}"
    return if visited.include?(key)

    visited.add(key)

    edges.next_from(resource).each do |other, verb|
      collector << {
        kind: other.class.to_s.split("::").last,
        name: other.name,
        verb: verb,
        depth: current_depth + 1
      }

      collect_impact(edges, other, current_depth + 1, max_depth, visited.dup, collector)
    end
  end

  def build_dependency_tree(db, resource, direction, current_depth, max_depth, visited)
    return [] if current_depth >= max_depth

    key = "#{resource.class.to_s.split("::").last}/#{resource.name}"
    return [] if visited.include?(key)

    visited.add(key)
    deps = []

    if direction == "outgoing"
      resource.class.relations.each do |verb, kind_name, _|
        rels = resource.relations(verb, kind_name)
        rels.each do |rel|
          deps << {
            kind: rel.class.to_s.split("::").last,
            name: rel.name,
            verb: verb.to_s,
            children: build_dependency_tree(db, rel, direction, current_depth + 1, max_depth, visited.dup)
          }
        end
      end
    elsif direction == "incoming"
      db.instances.each_value do |instances_hash|
        instances_hash.each_value do |other|
          next if other == resource

          other.class.relations.each do |verb, kind_name, _|
            rels = other.relations(verb, kind_name)
            next unless rels.include?(resource)

            deps << {
              kind: other.class.to_s.split("::").last,
              name: other.name,
              verb: verb.to_s,
              children: build_dependency_tree(db, other, direction, current_depth + 1, max_depth, visited.dup)
            }
          end
        end
      end
    end

    deps
  end
end
