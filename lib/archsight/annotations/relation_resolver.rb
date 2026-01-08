# frozen_string_literal: true

# ComputedRelationResolver provides methods for traversing resource relations.
# It mirrors the relation traversal operators in the query language:
# - outgoing (->): Direct outgoing relations
# - outgoing_transitive (~>): Transitive outgoing relations
# - incoming (<-): Direct incoming relations
# - incoming_transitive (<~): Transitive incoming relations
#
# Filter parameter can be:
# - Symbol: Simple kind filter (e.g., :TechnologyArtifact)
# - String: Query selector (e.g., 'TechnologyArtifact: activity/status == "active"')
class Archsight::Annotations::ComputedRelationResolver
  MAX_DEPTH = 10

  def initialize(instance, database)
    @instance = instance
    @database = database
    @query_cache = {}
  end

  # Get direct outgoing relations (-> Kind)
  # @param filter [Symbol, String, nil] Optional kind filter (Symbol) or query selector (String)
  # @return [Array] Array of related instances
  def outgoing(filter = nil)
    results = []

    @instance.class.relations.each do |_verb, kind_name, _klass_name|
      rels = @instance.relations(_verb, kind_name)
      rels.each do |rel|
        results << rel if matches_filter?(rel, filter)
      end
    end

    results.uniq
  end

  # Get transitive outgoing relations (~> Kind)
  # Follows all relation chains up to max_depth
  # @param filter [Symbol, String, nil] Optional kind filter (Symbol) or query selector (String)
  # @param max_depth [Integer] Maximum traversal depth (default 10)
  # @return [Array] Array of transitively related instances
  def outgoing_transitive(filter = nil, max_depth: MAX_DEPTH)
    visited = Set.new
    results = []

    collect_transitive_outgoing(@instance, filter, visited, 0, max_depth, results)
    results.uniq
  end

  # Get direct incoming relations (<- Kind)
  # Uses the references array maintained during relation resolution
  # @param filter [Symbol, String, nil] Optional kind filter (Symbol) or query selector (String)
  # @return [Array] Array of instances that reference this one
  def incoming(filter = nil)
    refs = @instance.references || []
    # Extract instances from reference hashes
    instances = refs.map { |ref| ref.is_a?(Hash) ? ref[:instance] : ref }.compact

    if filter.nil?
      instances
    else
      instances.select { |ref| matches_filter?(ref, filter) }
    end
  end

  # Get transitive incoming relations (<~ Kind)
  # Follows all reverse relation chains up to max_depth
  # @param filter [Symbol, String, nil] Optional kind filter (Symbol) or query selector (String)
  # @param max_depth [Integer] Maximum traversal depth (default 10)
  # @return [Array] Array of instances that transitively reference this one
  def incoming_transitive(filter = nil, max_depth: MAX_DEPTH)
    visited = Set.new
    results = []

    collect_transitive_incoming(@instance, filter, visited, 0, max_depth, results)
    results.uniq
  end

  private

  # Check if an instance matches the given filter
  # @param instance [Object] The instance to check
  # @param filter [Symbol, String, nil] Kind filter or query selector
  # @return [Boolean] true if instance matches
  def matches_filter?(instance, filter)
    return true if filter.nil?

    instance_kind = instance.class.name.split("::").last

    if filter.is_a?(Symbol)
      # Simple kind check
      instance_kind == filter.to_s
    else
      # Query selector - parse and evaluate
      query_node = parse_query(filter)
      evaluator.matches?(query_node, instance)
    end
  end

  # Parse a query string (with caching)
  def parse_query(query_string)
    @query_cache[query_string] ||= begin
      require_relative "../query/lexer"
      require_relative "../query/parser"
      tokens = Archsight::Query::Lexer.new(query_string).tokenize
      Archsight::Query::Parser.new(tokens).parse
    end
  end

  # Get or create the query evaluator
  def evaluator
    @evaluator ||= begin
      require_relative "../query/evaluator"
      Archsight::Query::Evaluator.new(@database)
    end
  end

  # Recursively collect transitive outgoing relations
  def collect_transitive_outgoing(inst, filter, visited, depth, max_depth, results)
    return if depth >= max_depth

    key = "#{inst.class}/#{inst.name}"
    return if visited.include?(key)

    visited.add(key)

    inst.class.relations.each do |verb, kind_name, _klass_name|
      rels = inst.relations(verb, kind_name)
      rels.each do |rel|
        # Add to results if matches filter (or no filter)
        results << rel if matches_filter?(rel, filter)

        # Continue traversal (regardless of whether this matched)
        collect_transitive_outgoing(rel, filter, visited.dup, depth + 1, max_depth, results)
      end
    end
  end

  # Recursively collect transitive incoming relations
  def collect_transitive_incoming(inst, filter, visited, depth, max_depth, results)
    return if depth >= max_depth

    key = "#{inst.class}/#{inst.name}"
    return if visited.include?(key)

    visited.add(key)

    refs = inst.references || []
    # Extract instances from reference hashes
    instances = refs.map { |ref| ref.is_a?(Hash) ? ref[:instance] : ref }.compact
    instances.each do |ref|
      # Add to results if matches filter (or no filter)
      results << ref if matches_filter?(ref, filter)

      # Continue traversal (regardless of whether this matched)
      collect_transitive_incoming(ref, filter, visited.dup, depth + 1, max_depth, results)
    end
  end
end
