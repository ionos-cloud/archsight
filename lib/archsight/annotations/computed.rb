# frozen_string_literal: true

require_relative "aggregators"
require_relative "relation_resolver"

# Computed represents a computed annotation definition.
# It stores the key, description, optional type, and the computation block.
class Archsight::Annotations::Computed
  attr_reader :key, :description, :type, :block

  def initialize(key, description: nil, type: nil, &block)
    @key = key
    @description = description
    @type = type
    @block = block
  end

  # Check if this definition matches a given key
  def matches?(other_key)
    @key == other_key
  end
end

# ComputedEvaluator provides the DSL context for computing annotation values.
# It exposes aggregation functions and relation traversal methods.
class Archsight::Annotations::ComputedEvaluator
  def initialize(instance, database, manager)
    @instance = instance
    @database = database
    @manager = manager
    @resolver = Archsight::Annotations::ComputedRelationResolver.new(instance, database)
  end

  # Access a regular annotation value from the current instance
  def annotation(key)
    @instance.annotations[key]
  end

  # Access a computed annotation value (triggers computation if needed)
  def computed(key)
    @manager.compute_for_key(@instance, key)
  end

  # --- Relation Traversal Methods ---

  # Get direct outgoing relations (-> Kind)
  def outgoing(kind = nil)
    @resolver.outgoing(kind)
  end

  # Get transitive outgoing relations (~> Kind)
  def outgoing_transitive(kind = nil, max_depth: 10)
    @resolver.outgoing_transitive(kind, max_depth: max_depth)
  end

  # Get direct incoming relations (<- Kind)
  def incoming(kind = nil)
    @resolver.incoming(kind)
  end

  # Get transitive incoming relations (<~ Kind)
  def incoming_transitive(kind = nil, max_depth: 10)
    @resolver.incoming_transitive(kind, max_depth: max_depth)
  end

  # --- Aggregation Functions ---

  # Sum numeric annotation values from instances
  # @param instances [Array] Array of resource instances
  # @param key [String] Annotation key to extract values from
  # @return [Float, nil] Sum of values or nil if no values
  def sum(instances, key)
    values = extract_values(instances, key)
    Archsight::Annotations::ComputedAggregators.sum(values)
  end

  # Count instances or non-nil annotation values
  # @param instances [Array] Array of resource instances
  # @param key [String, nil] Optional annotation key; if nil, counts instances
  # @return [Integer] Count
  def count(instances, key = nil)
    if key
      values = extract_values(instances, key)
      Archsight::Annotations::ComputedAggregators.count(values)
    else
      instances.length
    end
  end

  # Average numeric annotation values
  # @param instances [Array] Array of resource instances
  # @param key [String] Annotation key to extract values from
  # @return [Float, nil] Average or nil if no values
  def avg(instances, key)
    values = extract_values(instances, key)
    Archsight::Annotations::ComputedAggregators.avg(values)
  end

  # Minimum numeric annotation value
  # @param instances [Array] Array of resource instances
  # @param key [String] Annotation key to extract values from
  # @return [Float, nil] Minimum value or nil if no values
  def min(instances, key)
    values = extract_values(instances, key)
    Archsight::Annotations::ComputedAggregators.min(values)
  end

  # Maximum numeric annotation value
  # @param instances [Array] Array of resource instances
  # @param key [String] Annotation key to extract values from
  # @return [Float, nil] Maximum value or nil if no values
  def max(instances, key)
    values = extract_values(instances, key)
    Archsight::Annotations::ComputedAggregators.max(values)
  end

  # Collect unique annotation values
  # @param instances [Array] Array of resource instances
  # @param key [String] Annotation key to extract values from
  # @return [Array] Unique sorted values
  def collect(instances, key)
    values = extract_values(instances, key)
    Archsight::Annotations::ComputedAggregators.collect(values)
  end

  # Get first non-nil annotation value
  # @param instances [Array] Array of resource instances
  # @param key [String] Annotation key to extract values from
  # @return [Object, nil] First non-nil value
  def first(instances, key)
    values = extract_values(instances, key)
    Archsight::Annotations::ComputedAggregators.first(values)
  end

  # Get most common annotation value (mode)
  # @param instances [Array] Array of resource instances
  # @param key [String] Annotation key to extract values from
  # @return [Object, nil] Most frequent value
  def most_common(instances, key)
    values = extract_values(instances, key)
    Archsight::Annotations::ComputedAggregators.most_common(values)
  end

  # Get an annotation value from an instance, triggering computation if needed
  # @param instance [Object] Resource instance
  # @param key [String] Annotation key to extract
  # @return [Object, nil] Annotation value
  def get(instance, key)
    @manager.compute_for_key(instance, key) if instance.class.computed_annotations.any? { |d| d.matches?(key) }
    instance.annotations[key]
  end

  private

  # Extract annotation values from instances
  # If the key corresponds to a computed annotation that hasn't been computed yet,
  # trigger its computation to handle cross-kind dependencies
  def extract_values(instances, key)
    instances.map do |inst|
      # Check if this is a computed annotation that needs to be computed
      if inst.class.computed_annotations.any? { |d| d.matches?(key) }
        # Trigger computation if not already computed
        @manager.compute_for_key(inst, key)
      end
      inst.annotations[key]
    end
  end
end

# ComputedManager orchestrates the computation of all computed annotations.
# It handles lazy evaluation, caching, and cycle detection.
class Archsight::Annotations::ComputedManager
  def initialize(database)
    @database = database
    @computed_cache = {}  # { [instance_object_id, key] => value }
    @computing = Set.new  # For cycle detection
  end

  # Compute all computed annotations for all instances
  def compute_all!
    # Collect all resource classes that have computed annotations
    @database.instances.each do |klass, instances_hash|
      definitions = klass.computed_annotations
      next if definitions.empty?

      instances_hash.each_value do |instance|
        definitions.each do |definition|
          compute_for(instance, definition)
        end
      end
    end
  end

  # Compute a specific annotation for an instance by key
  def compute_for_key(instance, key)
    definition = instance.class.computed_annotations.find { |d| d.matches?(key) }
    return nil unless definition

    compute_for(instance, definition)
  end

  # Compute a specific annotation for an instance
  def compute_for(instance, definition)
    cache_key = [instance.object_id, definition.key]

    # Return cached value if available
    return @computed_cache[cache_key] if @computed_cache.key?(cache_key)

    # Cycle detection
    raise "Circular dependency detected: #{definition.key} for #{instance.name}" if @computing.include?(cache_key)

    @computing.add(cache_key)
    begin
      evaluator = Archsight::Annotations::ComputedEvaluator.new(instance, @database, self)
      value = evaluator.instance_eval(&definition.block)

      # Apply type coercion if specified
      value = coerce_value(value, definition.type) if definition.type

      # Cache the computed value (even if nil, to avoid recomputation)
      @computed_cache[cache_key] = value

      # Only store meaningful values to the instance annotations
      # nil and empty arrays indicate "no data" and should not be stored
      if meaningful_value?(value)
        # Convert arrays to comma-separated strings for consistency with regular annotations
        stored_value = value.is_a?(Array) ? value.join(", ") : value
        instance.set_computed_annotation(definition.key, stored_value)
      end

      value
    ensure
      @computing.delete(cache_key)
    end
  end

  private

  # Check if a value is meaningful (should be stored)
  # nil and empty collections indicate "no data" and should not be stored
  def meaningful_value?(value)
    return false if value.nil?
    return false if value.is_a?(Array) && value.empty?
    return false if value.is_a?(String) && value.empty?

    true
  end

  # Coerce value to specified type
  def coerce_value(value, type)
    return nil if value.nil?

    case type.to_s
    when "Integer"
      value.to_i
    when "Float"
      value.to_f
    when "String"
      value.to_s
    else
      value
    end
  end
end
