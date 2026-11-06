# frozen_string_literal: true

require_relative "base"
require_relative "../summary"

class Archsight::MCP::SummaryTool < FastMcp::Tool
  tool_name "summary"

  description <<~DESC.gsub("\n", " ").strip
    Explain a resource in context from its name: what it is (kind, layer, description, key facts) and how it fits in,
    as a short markdown summary. Which relations are followed depends on the layer of the resource (the lens):
    motivation = stakeholders, parent goals and refinements, requirements, evidence; strategy = what realizes and
    serves it; business = people, controls, products and contracts; application = interfaces, what it runs on, what
    depends on it, owners; technology = what it is built on, what runs on it, where it is, owners; implementation =
    plateau, gap and work package chain.

    Every resource in the summary is a link [[Kind/Name]]: take kind and name from it for the next call. A group
    that is cut off says how many more there are and the exact relations(...) call that lists them. Empty groups are
    not shown. A closing section points to the other layers that have related resources.

    EXAMPLES:
    name="Backup" - finds the resource of that name in any kind; several matches come back as a list to choose from
    kind="MotivationRequirement", name="R-7" - motivation lens: stakeholders, refinements, realized by, evidence
    kind="ApplicationComponent", name="checkout" - application lens: interfaces, runs on, used by, owners
    kind="TechnologyNode", name="node-1" - technology lens: runs on it, location, owners
    kind="BusinessProcess", name="Billing", lens="application" - the same resource through another layer's lens
    TYPICAL FLOW: query to find the name (or pass it directly), summary for the overview, then relations or
    analyze_resource for details. PITFALLS: the name is exact and case-sensitive (a close one is suggested); per_section
    only widens the lists, the summary stays bounded; lenses can be tuned per layer by a Config of type summary.
  DESC
  arguments do
    required(:name).filled(:string).description(
      "Name of the resource (or one of its aliases). Case-sensitive; without kind every kind is searched."
    )
    optional(:kind).filled(:string).description("Kind of the resource, to tell apart equal names, e.g. ApplicationComponent")
    optional(:lens).filled(:string).description(
      "View the resource through another layer's lens: #{Archsight::Resources::LAYERS.join(", ")}. Default: its own layer."
    )
    optional(:per_section).filled(:integer).description(
      "Resources listed per relation group (1-20, default 5). The overall size stays capped."
    )
  end

  def call(name:, kind: nil, lens: nil, per_section: 5)
    return error("Unknown lens: #{lens}. Use one of #{Archsight::Resources::LAYERS.join(", ")}") if lens && !Archsight::Resources::LAYERS.include?(lens)
    return error("Unknown resource kind: #{kind}") if kind && !Archsight::Resources[kind]

    found = resolve(name, kind)
    return not_found(name, kind) if found.empty?
    return ambiguous(name, found) if found.length > 1

    summarize(found.first, lens, per_section)
  rescue StandardError => e
    error("#{e.class}: #{e.message}")
  end

  private

  def summarize(instance, lens, per_section)
    markdown = Archsight::Summary::Builder.new(Archsight::MCP.db, per_section: per_section).call(instance, lens_layer: lens)
    JSON.pretty_generate({
      kind: instance.klass,
      name: instance.name,
      layer: instance.class.layer,
      lens: lens || instance.class.layer
    }.merge(Archsight::MCP.source_info(instance)).merge(summary: markdown))
  end

  # The resources called `name` (an alias counts, then the same name in another letter case), of `kind` or of any kind
  def resolve(name, kind)
    db = Archsight::MCP.db
    kinds = kind ? [kind] : db.instances.keys.map { |klass| klass.to_s.split("::").last }
    [
      -> { kinds.filter_map { |k| db.instance_by_kind(k, name) } },
      -> { kinds.filter_map { |k| db.instance_by_alias(k, name) } },
      -> { kinds.flat_map { |k| db.instances_by_kind(k).values.select { |i| i.name.to_s.casecmp?(name) } } }
    ].each do |attempt|
      found = attempt.call.uniq
      return found unless found.empty?
    end
    []
  end

  def ambiguous(name, found)
    candidates = found.sort_by { |i| [i.klass, i.name] }.map do |i|
      { kind: i.klass, name: i.name, link: "[[#{i.klass}/#{i.name}]]", description: Archsight::MCP.extract_description(i) }
    end
    JSON.pretty_generate({
                           ambiguous: true,
                           message: "#{found.length} resources are called #{name}; call summary again with kind set to one of them",
                           candidates: candidates
                         })
  end

  def not_found(name, kind)
    suggestions = Archsight::MCP.suggest(name, kind: kind)
    message = ["Resource not found: #{[kind, name].compact.join("/")}", Archsight::MCP.did_you_mean(suggestions)].compact.join(". ")
    JSON.pretty_generate({ error: "Error", message: message, suggestions: suggestions })
  end

  def error(message)
    JSON.pretty_generate({ error: "Error", message: message })
  end
end
