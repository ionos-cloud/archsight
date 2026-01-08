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
    ApplicationService, BusinessRequirement, ComplianceEvidence, and more.
  DESC
  arguments do
    required(:kind).filled(:string).description(
      "Resource type to analyze. Common kinds: TechnologyArtifact (repos, code), " \
      "ApplicationComponent (services), ApplicationInterface (APIs), " \
      "BusinessRequirement (compliance controls), ComplianceEvidence (compliance proof)"
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
    optional(:group_by).filled(:string).description(
      "How to group impact analysis results: " \
      "'kind' = group by resource type (default, good for understanding scope), " \
      "'verb' = group by relationship type (exposes, realizes, etc.), " \
      "'depth' = group by distance from target (1=direct, 2+=transitive)"
    )
  end

  def call(kind:, name:, depth: 0, impact: false, group_by: "kind")
    db = Archsight::MCP.db

    klass = Archsight::Resources[kind]
    return error_response("Unknown resource kind: #{kind}") unless klass

    instance = db.instance_by_kind(kind, name)
    return error_response("Resource not found: #{kind}/#{name}") unless instance

    depth = [[depth.to_i, 0].max, 10].min # Clamp to 0-10

    if impact
      build_impact_analysis(db, instance, kind, name, depth, group_by)
    else
      build_resource_analysis(db, instance, kind, name, depth)
    end
  rescue StandardError => e
    error_response(e.message, e.class.name, e.backtrace&.first(10))
  end

  private

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
    }

    if depth.positive?
      # Include dependency trees
      visited = Set.new
      result[:outgoing] = build_dependency_tree(db, instance, "outgoing", 0, depth, visited.dup)
      result[:incoming] = build_dependency_tree(db, instance, "incoming", 0, depth, visited.dup)
    else
      # Just direct relations
      result[:relations] = Archsight::MCP.extract_relations(instance)
      result[:has_relations] = instance.has_relations?
    end

    JSON.pretty_generate(result)
  end

  def build_impact_analysis(db, instance, kind, name, max_depth, group_by)
    max_depth = 5 if max_depth.zero? # Default depth for impact analysis

    # Collect all impacted resources
    impacted = []
    visited = Set.new
    collect_impact(db, instance, 0, max_depth, visited, impacted)

    # Group results
    grouped = case group_by
              when "verb"
                impacted.group_by { |i| i[:verb].to_s }
              when "kind"
                impacted.group_by { |i| i[:kind] }
              when "depth"
                impacted.group_by { |i| i[:depth] }
              else
                { "all" => impacted }
              end

    # Calculate summary statistics
    summary = {
      total_impacted: impacted.length,
      unique_resources: impacted.map { |i| "#{i[:kind]}/#{i[:name]}" }.uniq.length,
      by_kind: impacted.group_by { |i| i[:kind] }.transform_values(&:length),
      max_depth_reached: impacted.map { |i| i[:depth] }.max || 0
    }

    result = {
      target: { kind: kind, name: name },
      analysis: "impact",
      max_depth: max_depth,
      group_by: group_by,
      summary: summary,
      impacted_resources: grouped
    }

    JSON.pretty_generate(result)
  end

  def collect_impact(db, resource, current_depth, max_depth, visited, collector)
    return if current_depth >= max_depth

    key = "#{resource.class.to_s.split("::").last}/#{resource.name}"
    return if visited.include?(key)

    visited.add(key)

    db.instances.each_value do |instances_hash|
      instances_hash.each_value do |other|
        next if other == resource

        other.class.relations.each do |verb, kind_name, _|
          rels = other.relations(verb, kind_name)
          next unless rels.include?(resource)

          collector << {
            kind: other.class.to_s.split("::").last,
            name: other.name,
            verb: verb,
            depth: current_depth + 1
          }

          collect_impact(db, other, current_depth + 1, max_depth, visited.dup, collector)
        end
      end
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
