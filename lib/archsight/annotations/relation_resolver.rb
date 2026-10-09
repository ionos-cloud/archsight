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
  # The instances that refer to a resource through relations that are written in files. Computed annotations sum up the
  # modelled architecture (costs, teams, repositories): what a page or a description merely mentions or depicts (see
  # Archsight::References) must not change them, so they follow modelled relations only.
  def self.modelled_references(inst)
    (inst.references || []).filter_map do |ref|
      next ref unless ref.is_a?(Hash)

      ref[:instance] unless Archsight::Resources::DERIVED_VERBS.include?(ref[:verb])
    end
  end

  MAX_DEPTH = 10

  # TraversalCache holds what can be shared between all resolvers of one computation run: the unfiltered
  # transitive neighbourhood of an instance (relations are fixed once the database is verified), parsed filter
  # queries, one query evaluator and the short kind names. Filter results are never cached because they may
  # depend on computed annotations that are set while the run progresses.
  class TraversalCache
    def initialize(database)
      @database = database
      @reach = {}
      @queries = {}
      @kind_names = {}.compare_by_identity
    end

    # Short kind name of a resource class ("ApplicationComponent")
    def kind_name(klass)
      @kind_names[klass] ||= klass.name.split("::").last
    end

    # Parsed query for a selector string
    def query(selector)
      @queries[selector] ||= begin
        require_relative "../query/lexer"
        require_relative "../query/parser"
        Archsight::Query::Parser.new(Archsight::Query::Lexer.new(selector).tokenize).parse
      end
    end

    def evaluator
      @evaluator ||= begin
        require_relative "../query/evaluator"
        Archsight::Query::Evaluator.new(@database)
      end
    end

    # All instances reachable from `start` within max_depth hops (direction :outgoing or :incoming),
    # each once, in breadth-first order. `start` itself is included when a cycle leads back to it.
    def reachable(start, direction, max_depth)
      by_instance = (@reach[[direction, max_depth]] ||= {}.compare_by_identity)
      by_instance[start] ||= walk(start, direction, max_depth)
    end

    private

    def walk(start, direction, max_depth)
      results = []
      listed = {}.compare_by_identity
      expanded = { start => true }.compare_by_identity
      frontier = [start]
      depth = 0
      while depth < max_depth && !frontier.empty?
        following = []
        frontier.each do |node|
          neighbours(node, direction).each do |other|
            unless listed.key?(other)
              listed[other] = true
              results << other
            end
            next if expanded.key?(other)

            expanded[other] = true
            following << other
          end
        end
        frontier = following
        depth += 1
      end
      results
    end

    def neighbours(inst, direction)
      if direction == :outgoing
        inst.class.declared_relations.flat_map { |verb, kind_name, _klass_name| inst.relations(verb, kind_name) }
      else
        Archsight::Annotations::ComputedRelationResolver.modelled_references(inst)
      end
    end
  end

  # @param cache [TraversalCache, nil] shared per computation run; a private one is created when omitted
  def initialize(instance, database, cache = nil)
    @instance = instance
    @database = database
    @cache = cache || TraversalCache.new(database)
  end

  # Get direct outgoing relations (-> Kind)
  # @param filter [Symbol, String, nil] Optional kind filter (Symbol) or query selector (String)
  # @return [Array] Array of related instances
  def outgoing(filter = nil)
    results = []

    @instance.class.declared_relations.each do |_verb, kind_name, _klass_name|
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
    filtered(@cache.reachable(@instance, :outgoing, max_depth), filter)
  end

  # Get direct incoming relations (<- Kind)
  # Uses the references array maintained during relation resolution
  # @param filter [Symbol, String, nil] Optional kind filter (Symbol) or query selector (String)
  # @return [Array] Array of instances that reference this one
  def incoming(filter = nil)
    instances = self.class.modelled_references(@instance).compact

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
    filtered(@cache.reachable(@instance, :incoming, max_depth), filter)
  end

  private

  def filtered(instances, filter)
    return instances.dup if filter.nil?

    if filter.is_a?(Symbol)
      kind = filter.to_s
      instances.select { |inst| @cache.kind_name(inst.class) == kind }
    else
      query_node = @cache.query(filter)
      instances.select { |inst| @cache.evaluator.matches?(query_node, inst) }
    end
  end

  # Check if an instance matches the given filter
  # @param instance [Object] The instance to check
  # @param filter [Symbol, String, nil] Kind filter or query selector
  # @return [Boolean] true if instance matches
  def matches_filter?(instance, filter)
    return true if filter.nil?

    if filter.is_a?(Symbol)
      @cache.kind_name(instance.class) == filter.to_s
    else
      @cache.evaluator.matches?(@cache.query(filter), instance)
    end
  end
end
