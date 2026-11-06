# frozen_string_literal: true

require_relative "base"
require_relative "query_hints"

class Archsight::MCP::QueryTool < FastMcp::Tool
  tool_name "query"

  description <<~DESC.gsub("\n", " ").strip
    Search and filter architecture resources using a powerful query language.

    QUERY SYNTAX:

    • Name search: 'kubernetes' (shortcut for name =~ "kubernetes"), 'name == "ExactName"', 'name =~ "pattern"'

    • Kind filter prefix: 'TechnologyArtifact: ...' restricts search to that resource type

    • Annotation filters: 'activity/status == "active"', 'scc/language/Go/loc > 5000'
      Operators: == (equals), != (not equals), =~ (regex match), >, <, >=, <=

    • Free-text search over the string annotations (descriptions, links, titles, ...):
      text =~ "failover" (also text: "failover"; case-insensitive regex, like name =~)
      text(architecture/description) =~ "x", text(link/*, page/content) =~ "x" restrict the keys (* = any run)
      Each hit shows matched_text: the annotation key and a snippet around the match.

    • Relation queries:
      -> Kind (has outgoing relation to kind), -> "Name" (to specific instance)
      <- Kind (has incoming relation from kind), <- "Name" (from specific instance)
      ~> Kind (transitively reaches), <~ Kind (transitively reached by)
      -> none (no outgoing relations), <- none (no incoming relations / orphan detection)

    • Sub-query targets: $(expression) - dynamic relation matching
      -> $(expr) (relates to any resource matching expr)
      ~> $(expr) (transitively reaches any matching resource)
      <- $(expr) (incoming from any matching resource)

    • Logical operators: AND/and/&, OR/or/|, NOT/not/!, parentheses for grouping

    EXAMPLES:
    'kubernetes' - resources with "kubernetes" in name
    'TechnologyArtifact: activity/status == "active"' - active TechnologyArtifacts
    '-> ApplicationInterface & repository/artifacts == "container"' - containerized services exposing APIs
    '<- none' - resources not referenced by anything (potential orphans)
    '-> none & <- none' - true orphans with no relations at all
    '~> $(web-checkout)' - transitively reaches instance matching "web-checkout"
    '<- $(TechnologyArtifact: activity/status == "active")' - referenced by active artifacts
    'ApplicationComponent: <- none & -> none' - components nothing refers to and that refer to nothing (orphans of one kind)
    'ApplicationComponent: ~> $(name == "web-checkout")' - components that transitively reach web-checkout
    'ApplicationService: -{realizedThrough}> ApplicationComponent' - only along one relation verb (<{verb}- for incoming)
    'ApplicationService: text =~ "failover" & -> ApplicationComponent' - services whose text mentions failover and that have components
    'text(link/*) =~ "PROJ-1234"' - every resource that links ticket PROJ-1234
    For the impact of changing a resource use analyze_resource(impact=true) with kinds/exclude_kinds/depth/limit.

    TYPICAL FLOW: find the exact name with a name search (output='brief' shows kind, name and source file),
    then call analyze_resource or relations with that kind and name. Use output='count' first to see how big
    a result is, 'brief' to list it, and 'complete' (with fields=[...] and a small limit) only for details.

    PITFALLS:
    • A filter on an annotation key that does not exist matches nothing; the result then carries a warning
      'unknown annotation key ...' listing the known keys. Keys are exact and case-sensitive.
    • Annotation values are strings: compare with == "x", numbers with > < >=, regex with =~.
    • output='complete' returns every annotation and relation of each hit: combine it with fields and limit.
    • Add a Kind: prefix when you can; without it every kind is searched, which is slower and noisier.
    • Pages and menus are resources too (Page, PageMenu): exclude them with a Kind: prefix when you look for architecture.
  DESC
  arguments do
    required(:query).filled(:string).description(
      "Query string using the query language syntax. " \
      'Examples: \'kubernetes\', \'TechnologyArtifact: activity/status == "active"\', ' \
      "'-> ApplicationInterface', '<- none'"
    )
    optional(:output).filled(:string).description(
      "Output format: " \
      "'complete' = full resource details including annotations and relations (default), " \
      "'brief' = minimal output with just kind and name for each resource, " \
      "'count' = only totals grouped by kind, no individual resources returned"
    )
    optional(:fields).array(:string).description(
      "Only these annotation keys and relation verbs in output='complete' " \
      "(e.g. ['activity/status', 'maintainedBy']). Default: all. Keeps results small."
    )
    optional(:limit).filled(:integer).description(
      "Maximum results to return (1-500). Use with offset for pagination. Ignored when output='count'."
    )
    optional(:offset).filled(:integer).description(
      "Number of results to skip. Use with limit for pagination (e.g., offset=50, limit=50 for page 2). " \
      "Ignored when output='count'."
    )
  end

  def call(query:, output: "complete", limit: 50, offset: 0, fields: nil)
    db = Archsight::MCP.db

    begin
      parsed_query = Archsight::Query.parse(query)
      results = parsed_query.filter(db)
      total = results.length

      # Complete output omits the kind when filtering by a specific kind (it's redundant); brief always names
      # it, so a hit can feed analyze_resource(kind, name) without guessing
      omit_kind = !parsed_query.kind_filter.nil?

      conditions = Archsight::MCP::QueryHints.relation_conditions(parsed_query.ast)
      text_conditions = Archsight::MCP::QueryHints.text_conditions(parsed_query.ast)

      # Count-only mode: return totals grouped by kind
      if output == "count"
        by_kind = results.group_by { |r| r.class.to_s.split("::").last }
                         .transform_values(&:length)

        result = {
          query: query,
          total: total,
          by_kind: by_kind
        }
      else
        # Complete or brief mode: return paginated resources
        paginated = results.sort_by(&:name).drop(offset).take(limit)
        resources = case output
                    when "brief"
                      paginated.map { |r| Archsight::MCP.brief_summary(r, with_source: true) }
                    else # "complete"
                      paginated.map do |r|
                        summary = Archsight::MCP.complete_summary(r, omit_kind: omit_kind, with_source: true)
                        Archsight::MCP.project(summary, fields)
                      end
                    end

        add_matched_via(resources, paginated, conditions)
        add_matched_text(resources, paginated, text_conditions)

        result = {
          query: query,
          total: total,
          limit: limit,
          offset: offset,
          count: paginated.length,
          resources: resources
        }
      end

      warnings = Archsight::MCP::QueryHints.unknown_key_warnings(parsed_query)
      result = result.merge(warnings: warnings) unless warnings.empty?

      fit_response(result, output, fields)
    rescue Archsight::Query::QueryError => e
      JSON.pretty_generate({
                             error: "Query error",
                             message: e.message,
                             query: query
                           })
    end
  end

  private

  # For text queries (`text =~ "x"`): the annotation and the snippet around the match, per hit
  def add_matched_text(summaries, resources, conditions)
    return if conditions.empty?

    summaries.zip(resources).each do |summary, resource|
      found = Archsight::MCP::QueryHints.matched_text(resource, conditions)
      summary[:matched_text] = found unless found.empty?
    end
  end

  # For relation queries (`-> Kind`, `<- "Name"`): the direct relations that made each hit match
  def add_matched_via(summaries, resources, conditions)
    return if conditions.empty?

    summaries.zip(resources).each do |summary, resource|
      via = Archsight::MCP::QueryHints.matched_via(resource, conditions)
      summary[:matched_via] = via unless via.empty?
    end
  end

  # Cuts the resources of an oversized result down (halving until it fits) and says how to get the rest
  def fit_response(result, output, fields)
    return JSON.pretty_generate(result) unless result[:resources]

    full = result[:resources]
    Archsight::MCP.fit(result) do |attempt|
      keep = [full.length / (2**attempt), 1].max
      result.merge(
        resources: full.take(keep),
        count: keep,
        truncated: "Response cut to #{keep} of #{full.length} resources (size budget). " \
                   "#{hint_for(output, fields)}"
      )
    end
  end

  def hint_for(output, fields)
    return "Use a smaller limit with offset, or output='brief'/'count'." if output == "complete" && fields.nil?

    "Use a smaller limit with offset."
  end
end
