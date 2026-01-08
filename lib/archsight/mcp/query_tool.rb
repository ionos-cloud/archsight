# frozen_string_literal: true

require_relative "base"

class Archsight::MCP::QueryTool < FastMcp::Tool
  tool_name "query"

  description <<~DESC.gsub("\n", " ").strip
    Search and filter architecture resources using a powerful query language.

    QUERY SYNTAX:

    • Name search: 'kubernetes' (shortcut for name =~ "kubernetes"), 'name == "ExactName"', 'name =~ "pattern"'

    • Kind filter prefix: 'TechnologyArtifact: ...' restricts search to that resource type

    • Annotation filters: 'activity/status == "active"', 'scc/language/Go/loc > 5000'
      Operators: == (equals), != (not equals), =~ (regex match), >, <, >=, <=

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
    '~> $(dcd-mf-dcxpress)' - transitively reaches instance matching "dcd-mf-dcxpress"
    '<- $(TechnologyArtifact: activity/status == "active")' - referenced by active artifacts
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
    optional(:limit).filled(:integer).description(
      "Maximum results to return (1-500). Use with offset for pagination. Ignored when output='count'."
    )
    optional(:offset).filled(:integer).description(
      "Number of results to skip. Use with limit for pagination (e.g., offset=50, limit=50 for page 2). " \
      "Ignored when output='count'."
    )
  end

  def call(query:, output: "complete", limit: 50, offset: 0)
    db = Archsight::MCP.db

    begin
      parsed_query = Archsight::Query.parse(query)
      results = parsed_query.filter(db)
      total = results.length

      # Omit kind from output when filtering by a specific kind (it's redundant)
      omit_kind = !parsed_query.kind_filter.nil?

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
                      paginated.map { |r| Archsight::MCP.brief_summary(r, omit_kind: omit_kind) }
                    else # "complete"
                      paginated.map { |r| Archsight::MCP.complete_summary(r, omit_kind: omit_kind) }
                    end

        result = {
          query: query,
          total: total,
          limit: limit,
          offset: offset,
          count: paginated.length,
          resources: resources
        }
      end

      JSON.pretty_generate(result)
    rescue Archsight::Query::QueryError => e
      JSON.pretty_generate({
                             error: "Query error",
                             message: e.message,
                             query: query
                           })
    end
  end
end
