# frozen_string_literal: true

require_relative "errors"
require_relative "ast"

class Archsight::Query::Evaluator
  def initialize(database)
    @database = database
    @subquery_cache = {} # Cache for pre-computed subquery results
  end

  # Main entry point: evaluate query against instance, returns boolean
  def matches?(query_node, instance)
    # Check kind filter first
    if query_node.kind_filter
      instance_kind = instance.class.to_s.split("::").last
      return false unless instance_kind == query_node.kind_filter
    end

    # If no expression, kind filter alone is sufficient (match all of that kind)
    return true if query_node.expression.nil?

    # Pre-compute subqueries for this evaluation
    @subquery_cache = {}
    precompute_subqueries(query_node.expression)

    evaluate(query_node.expression, instance)
  end

  # Filter all instances matching query
  def filter(query_node)
    results = []

    target_instances = if query_node.kind_filter
                         klass = Archsight::Resources[query_node.kind_filter]
                         return [] unless klass

                         @database.instances[klass]&.values || []
                       else
                         all = []
                         @database.instances.each_value { |h| all.concat(h.values) }
                         all
                       end

    # If no expression, return all target instances (kind filter only)
    return target_instances if query_node.expression.nil?

    # Pre-compute ALL subqueries before the main filter loop
    # This is the key optimization - subqueries are evaluated once, not per-instance
    @subquery_cache = {}
    precompute_subqueries(query_node.expression)

    target_instances.each do |instance|
      results << instance if evaluate(query_node.expression, instance)
    end

    results
  end

  private

  # Recursively find and pre-compute all subqueries in the AST
  def precompute_subqueries(node)
    case node
    when Archsight::Query::AST::BinaryOp
      precompute_subqueries(node.left)
      precompute_subqueries(node.right)
    when Archsight::Query::AST::NotOp
      precompute_subqueries(node.operand)
    when Archsight::Query::AST::OutgoingDirectRelation, Archsight::Query::AST::OutgoingTransitiveRelation,
         Archsight::Query::AST::IncomingDirectRelation, Archsight::Query::AST::IncomingTransitiveRelation
      precompute_subquery_target(node.target)
    end
  end

  def precompute_subquery_target(target)
    return unless target.is_a?(Archsight::Query::AST::SubqueryTarget)

    # Use the subquery's object_id as cache key
    cache_key = target.object_id
    return if @subquery_cache.key?(cache_key)

    # First, recursively precompute any nested subqueries
    precompute_subqueries(target.query.expression) if target.query.expression

    # Then compute this subquery's results
    @subquery_cache[cache_key] = Set.new(filter_without_cache(target.query))
  end

  # Filter without using/populating the cache (used during precomputation)
  def filter_without_cache(query_node)
    results = []

    target_instances = if query_node.kind_filter
                         klass = Archsight::Resources[query_node.kind_filter]
                         return [] unless klass

                         @database.instances[klass]&.values || []
                       else
                         all = []
                         @database.instances.each_value { |h| all.concat(h.values) }
                         all
                       end

    return target_instances if query_node.expression.nil?

    target_instances.each do |instance|
      results << instance if evaluate(query_node.expression, instance)
    end

    results
  end

  # Get cached subquery results, or compute if not cached
  def get_subquery_results(subquery_target)
    cache_key = subquery_target.object_id
    @subquery_cache[cache_key] ||= Set.new(filter_without_cache(subquery_target.query))
  end

  # Check if a verb matches the verb filter
  # Returns true if the verb should be included in traversal
  def verb_matches?(verb, verbs, exclude_mode)
    return true if verbs.nil? # nil = all verbs (no filter)

    if exclude_mode
      # Denylist: match if verb is NOT in the list
      !verbs.include?(verb.to_s)
    else
      # Allowlist: match if verb IS in the list
      verbs.include?(verb.to_s)
    end
  end

  def evaluate(node, instance)
    case node
    when Archsight::Query::AST::BinaryOp
      evaluate_binary_op(node, instance)
    when Archsight::Query::AST::NotOp
      evaluate_not_op(node, instance)
    when Archsight::Query::AST::AnnotationCondition
      evaluate_annotation_condition(node, instance)
    when Archsight::Query::AST::AnnotationExistsCondition
      evaluate_annotation_exists_condition(node, instance)
    when Archsight::Query::AST::AnnotationInCondition
      evaluate_annotation_in_condition(node, instance)
    when Archsight::Query::AST::KindCondition
      evaluate_kind_condition(node, instance)
    when Archsight::Query::AST::KindInCondition
      evaluate_kind_in_condition(node, instance)
    when Archsight::Query::AST::NameCondition
      evaluate_name_condition(node, instance)
    when Archsight::Query::AST::NameInCondition
      evaluate_name_in_condition(node, instance)
    when Archsight::Query::AST::OutgoingDirectRelation
      evaluate_outgoing_direct_relation(node, instance)
    when Archsight::Query::AST::OutgoingTransitiveRelation
      evaluate_outgoing_transitive_relation(node, instance)
    when Archsight::Query::AST::IncomingDirectRelation
      evaluate_incoming_direct_relation(node, instance)
    when Archsight::Query::AST::IncomingTransitiveRelation
      evaluate_incoming_transitive_relation(node, instance)
    else
      raise Archsight::Query::EvaluationError, "Unknown AST node type: #{node.class}"
    end
  end

  def evaluate_binary_op(node, instance)
    case node.operator
    when :and
      # Short-circuit: if left is false, don't evaluate right
      evaluate(node.left, instance) && evaluate(node.right, instance)
    when :or
      # Short-circuit: if left is true, don't evaluate right
      evaluate(node.left, instance) || evaluate(node.right, instance)
    end
  end

  def evaluate_not_op(node, instance)
    !evaluate(node.operand, instance)
  end

  def evaluate_annotation_exists_condition(node, instance)
    annotation_value = instance.annotations[node.path]
    # Return true if annotation exists and has a non-empty value
    !annotation_value.nil? && annotation_value.to_s.strip != ""
  end

  def evaluate_annotation_in_condition(node, instance)
    annotation_value = instance.annotations[node.path]
    return false unless annotation_value

    annotation = instance.class.annotation_matching(node.path)
    is_list = annotation&.list?

    query_values = node.values.map { |v| v.value.to_s }

    if is_list
      # For list annotations, check if any query value matches any annotation value
      annotation_values = annotation_value.to_s.split(",").map(&:strip)
      annotation_values.intersect?(query_values)
    else
      # For regular annotations, check if annotation value matches any query value
      query_values.include?(annotation_value.to_s)
    end
  end

  def evaluate_annotation_condition(node, instance)
    annotation_value = instance.annotations[node.path]
    annotation = instance.class.annotation_matching(node.path)

    # Handle != for missing annotations (they match != condition)
    return true if node.operator == "!=" && annotation_value.nil?

    return false unless annotation_value

    query_value = extract_query_value(node.value)
    is_list = annotation&.list?

    case node.operator
    when "=="
      if node.value.is_a?(Archsight::Query::AST::NumberValue)
        # Numeric equality comparison
        compare_numeric_equality(annotation_value, query_value)
      elsif is_list
        values = annotation_value.to_s.split(",").map(&:strip)
        values.include?(query_value.to_s)
      else
        annotation_value.to_s == query_value.to_s
      end
    when "!="
      if node.value.is_a?(Archsight::Query::AST::NumberValue)
        # Numeric inequality comparison
        !compare_numeric_equality(annotation_value, query_value)
      elsif is_list
        values = annotation_value.to_s.split(",").map(&:strip)
        !values.include?(query_value.to_s)
      else
        annotation_value.to_s != query_value.to_s
      end
    when "=~"
      regex = build_regex_from_value(node.value)
      if is_list
        values = annotation_value.to_s.split(",").map(&:strip)
        values.any? { |v| regex.match?(v) }
      else
        regex.match?(annotation_value.to_s)
      end
    when ">", "<", ">=", "<="
      compare_numeric_fallback(annotation_value, query_value, node.operator)
    else
      false
    end
  end

  def extract_query_value(value_node)
    case value_node
    when Archsight::Query::AST::NumberValue
      value_node.value
    when Archsight::Query::AST::RegexValue
      value_node.value
    else
      value_node.value.to_s
    end
  end

  def build_regex_from_value(value_node)
    if value_node.is_a?(Archsight::Query::AST::RegexValue)
      value_node.to_regexp
    else
      Regexp.new(value_node.value.to_s, Regexp::IGNORECASE)
    end
  end

  def compare_numeric_fallback(annotation_value, query_value, operator)
    left = annotation_value.to_f
    right = query_value.to_f
    case operator
    when ">" then left > right
    when "<" then left < right
    when ">=" then left >= right
    when "<=" then left <= right
    else false
    end
  rescue StandardError
    false
  end

  def compare_numeric_equality(annotation_value, query_value)
    annotation_value.to_f == query_value.to_f
  rescue StandardError
    false
  end

  def evaluate_kind_condition(node, instance)
    instance_kind = instance.class.to_s.split("::").last

    case node.operator
    when "=="
      instance_kind == node.value.value.to_s
    when "=~"
      regex = build_regex_from_value(node.value)
      !!(instance_kind =~ regex)
    else
      false
    end
  end

  def evaluate_kind_in_condition(node, instance)
    instance_kind = instance.class.to_s.split("::").last
    query_values = node.values.map { |v| v.value.to_s }
    query_values.include?(instance_kind)
  end

  def evaluate_name_condition(node, instance)
    name = instance.name
    return false unless name

    case node.operator
    when "=="
      name == node.value.value.to_s
    when "!="
      name != node.value.value.to_s
    when "=~"
      re = if node.value.is_a?(Archsight::Query::AST::RegexValue)
             node.value.to_regexp
           else
             Regexp.new(node.value.value.to_s, Regexp::IGNORECASE)
           end
      !!(name =~ re)
    else
      false
    end
  end

  def evaluate_name_in_condition(node, instance)
    name = instance.name
    return false unless name

    query_values = node.values.map { |v| v.value.to_s }
    query_values.include?(name)
  end

  # Outgoing relations: what does this resource point to?

  def evaluate_outgoing_direct_relation(node, instance)
    verbs = node.verbs
    exclude_verbs = node.exclude_verbs

    case node.target
    when Archsight::Query::AST::KindTarget
      has_outgoing_relation_to_kind?(instance, node.target.kind_name, verbs, exclude_verbs)
    when Archsight::Query::AST::InstanceTarget
      has_outgoing_relation_to_instance?(instance, node.target.instance_name, verbs, exclude_verbs)
    when Archsight::Query::AST::NothingTarget
      !has_any_outgoing_relations?(instance, verbs, exclude_verbs)
    when Archsight::Query::AST::SubqueryTarget
      has_outgoing_relation_to_subquery?(instance, node.target, verbs, exclude_verbs)
    end
  end

  def evaluate_outgoing_transitive_relation(node, instance)
    visited = Set.new
    max_depth = node.max_depth
    verbs = node.verbs
    exclude_verbs = node.exclude_verbs

    case node.target
    when Archsight::Query::AST::KindTarget
      reaches_kind_transitively?(instance, node.target.kind_name, visited, 0, max_depth, verbs, exclude_verbs)
    when Archsight::Query::AST::InstanceTarget
      reaches_instance_transitively?(instance, node.target.instance_name, visited, 0, max_depth, verbs,
                                     exclude_verbs)
    when Archsight::Query::AST::NothingTarget
      # ~> # is treated same as -> # (no outgoing relations)
      !has_any_outgoing_relations?(instance, verbs, exclude_verbs)
    when Archsight::Query::AST::SubqueryTarget
      reaches_subquery_transitively?(instance, node.target, visited, 0, max_depth, nil, verbs, exclude_verbs)
    end
  end

  def has_outgoing_relation_to_kind?(instance, target_kind, verbs = nil, exclude_verbs = false)
    instance.class.relations.each do |verb, kind_name, _|
      next unless verb_matches?(verb, verbs, exclude_verbs)

      rels = instance.relations(verb, kind_name)
      rels.each do |rel|
        rel_kind = rel.class.to_s.split("::").last
        return true if rel_kind == target_kind
      end
    end
    false
  end

  def has_outgoing_relation_to_instance?(instance, target_name, verbs = nil, exclude_verbs = false)
    instance.class.relations.each do |verb, kind_name, _|
      next unless verb_matches?(verb, verbs, exclude_verbs)

      rels = instance.relations(verb, kind_name)
      return true if rels.any? { |rel| rel.name == target_name }
    end
    false
  end

  def has_any_outgoing_relations?(instance, verbs = nil, exclude_verbs = false)
    instance.class.relations.each do |verb, kind_name, _|
      next unless verb_matches?(verb, verbs, exclude_verbs)

      rels = instance.relations(verb, kind_name)
      return true if rels.any?
    end
    false
  end

  def reaches_kind_transitively?(instance, target_kind, visited, depth, max_depth, verbs = nil,
                                 exclude_verbs = false)
    return false if depth >= max_depth

    key = "#{instance.class}/#{instance.name}"
    return false if visited.include?(key)

    visited.add(key)

    instance.class.relations.each do |verb, kind_name, _|
      next unless verb_matches?(verb, verbs, exclude_verbs)

      rels = instance.relations(verb, kind_name)
      rels.each do |rel|
        rel_kind = rel.class.to_s.split("::").last
        return true if rel_kind == target_kind
        return true if reaches_kind_transitively?(rel, target_kind, visited.dup, depth + 1, max_depth, verbs,
                                                  exclude_verbs)
      end
    end

    false
  end

  def reaches_instance_transitively?(instance, target_name, visited, depth, max_depth, verbs = nil,
                                     exclude_verbs = false)
    return false if depth >= max_depth

    key = "#{instance.class}/#{instance.name}"
    return false if visited.include?(key)

    visited.add(key)

    instance.class.relations.each do |verb, kind_name, _|
      next unless verb_matches?(verb, verbs, exclude_verbs)

      rels = instance.relations(verb, kind_name)
      rels.each do |rel|
        return true if rel.name == target_name
        return true if reaches_instance_transitively?(rel, target_name, visited.dup, depth + 1, max_depth, verbs,
                                                      exclude_verbs)
      end
    end

    false
  end

  # Incoming relations: what points to this resource?

  def evaluate_incoming_direct_relation(node, instance)
    verbs = node.verbs
    exclude_verbs = node.exclude_verbs

    case node.target
    when Archsight::Query::AST::KindTarget
      has_incoming_relation_from_kind?(instance, node.target.kind_name, verbs, exclude_verbs)
    when Archsight::Query::AST::InstanceTarget
      has_incoming_relation_from_instance?(instance, node.target.instance_name, verbs, exclude_verbs)
    when Archsight::Query::AST::NothingTarget
      !has_any_incoming_relations?(instance, verbs, exclude_verbs)
    when Archsight::Query::AST::SubqueryTarget
      has_incoming_relation_from_subquery?(instance, node.target, verbs, exclude_verbs)
    end
  end

  def evaluate_incoming_transitive_relation(node, instance)
    visited = Set.new
    max_depth = node.max_depth
    verbs = node.verbs
    exclude_verbs = node.exclude_verbs

    case node.target
    when Archsight::Query::AST::KindTarget
      reached_by_kind_transitively?(instance, node.target.kind_name, visited, 0, max_depth, verbs, exclude_verbs)
    when Archsight::Query::AST::InstanceTarget
      reached_by_instance_transitively?(instance, node.target.instance_name, visited, 0, max_depth, verbs,
                                        exclude_verbs)
    when Archsight::Query::AST::NothingTarget
      # <~ # is treated same as <- # (no incoming relations)
      !has_any_incoming_relations?(instance, verbs, exclude_verbs)
    when Archsight::Query::AST::SubqueryTarget
      reached_by_subquery_transitively?(instance, node.target, visited, 0, max_depth, nil, verbs, exclude_verbs)
    end
  end

  def has_incoming_relation_from_kind?(instance, source_kind, verbs = nil, exclude_verbs = false)
    @database.instances.each_value do |instances_hash|
      instances_hash.each_value do |other|
        next if other == instance

        other_kind = other.class.to_s.split("::").last
        next unless other_kind == source_kind

        other.class.relations.each do |verb, kind_name, _|
          next unless verb_matches?(verb, verbs, exclude_verbs)

          rels = other.relations(verb, kind_name)
          return true if rels.include?(instance)
        end
      end
    end
    false
  end

  def has_incoming_relation_from_instance?(instance, source_name, verbs = nil, exclude_verbs = false)
    @database.instances.each_value do |instances_hash|
      instances_hash.each_value do |other|
        next if other == instance
        next unless other.name == source_name

        other.class.relations.each do |verb, kind_name, _|
          next unless verb_matches?(verb, verbs, exclude_verbs)

          rels = other.relations(verb, kind_name)
          return true if rels.include?(instance)
        end
      end
    end
    false
  end

  def has_any_incoming_relations?(instance, verbs = nil, exclude_verbs = false)
    @database.instances.each_value do |instances_hash|
      instances_hash.each_value do |other|
        next if other == instance

        other.class.relations.each do |verb, kind_name, _|
          next unless verb_matches?(verb, verbs, exclude_verbs)

          rels = other.relations(verb, kind_name)
          return true if rels.include?(instance)
        end
      end
    end
    false
  end

  def reached_by_kind_transitively?(instance, source_kind, visited, depth, max_depth, verbs = nil,
                                    exclude_verbs = false)
    return false if depth >= max_depth

    key = "#{instance.class}/#{instance.name}"
    return false if visited.include?(key)

    visited.add(key)

    @database.instances.each_value do |instances_hash|
      instances_hash.each_value do |other|
        next if other == instance

        other.class.relations.each do |verb, kind_name, _|
          next unless verb_matches?(verb, verbs, exclude_verbs)

          rels = other.relations(verb, kind_name)
          next unless rels.include?(instance)

          other_kind = other.class.to_s.split("::").last
          return true if other_kind == source_kind
          return true if reached_by_kind_transitively?(other, source_kind, visited.dup, depth + 1, max_depth,
                                                       verbs, exclude_verbs)
        end
      end
    end

    false
  end

  def reached_by_instance_transitively?(instance, source_name, visited, depth, max_depth, verbs = nil,
                                        exclude_verbs = false)
    return false if depth >= max_depth

    key = "#{instance.class}/#{instance.name}"
    return false if visited.include?(key)

    visited.add(key)

    @database.instances.each_value do |instances_hash|
      instances_hash.each_value do |other|
        next if other == instance

        other.class.relations.each do |verb, kind_name, _|
          next unless verb_matches?(verb, verbs, exclude_verbs)

          rels = other.relations(verb, kind_name)
          next unless rels.include?(instance)

          return true if other.name == source_name
          return true if reached_by_instance_transitively?(other, source_name, visited.dup, depth + 1, max_depth,
                                                           verbs, exclude_verbs)
        end
      end
    end

    false
  end

  # Subquery relation methods

  # Check if instance has any outgoing relation to any instance matching the subquery
  def has_outgoing_relation_to_subquery?(instance, subquery_target, verbs = nil, exclude_verbs = false)
    # Use cached subquery results for O(1) lookup
    target_set = get_subquery_results(subquery_target)
    return false if target_set.empty?

    instance.class.relations.each do |verb, kind_name, _|
      next unless verb_matches?(verb, verbs, exclude_verbs)

      rels = instance.relations(verb, kind_name)
      rels.each do |rel|
        return true if target_set.include?(rel)
      end
    end
    false
  end

  # Check if instance transitively reaches any instance matching the subquery
  def reaches_subquery_transitively?(instance, subquery_target, visited, depth, max_depth, _unused = nil,
                                     verbs = nil, exclude_verbs = false)
    return false if depth >= max_depth

    key = "#{instance.class}/#{instance.name}"
    return false if visited.include?(key)

    visited.add(key)

    # Use cached subquery results - computed once before filter loop
    target_set = get_subquery_results(subquery_target)
    return false if target_set.empty?

    instance.class.relations.each do |verb, kind_name, _|
      next unless verb_matches?(verb, verbs, exclude_verbs)

      rels = instance.relations(verb, kind_name)
      rels.each do |rel|
        return true if target_set.include?(rel)
        return true if reaches_subquery_transitively?(rel, subquery_target, visited.dup, depth + 1, max_depth, nil,
                                                      verbs, exclude_verbs)
      end
    end

    false
  end

  # Check if any instance matching the subquery has a direct relation to this instance
  def has_incoming_relation_from_subquery?(instance, subquery_target, verbs = nil, exclude_verbs = false)
    # Use cached subquery results
    source_set = get_subquery_results(subquery_target)
    return false if source_set.empty?

    source_set.each do |source|
      source.class.relations.each do |verb, kind_name, _|
        next unless verb_matches?(verb, verbs, exclude_verbs)

        rels = source.relations(verb, kind_name)
        return true if rels.include?(instance)
      end
    end
    false
  end

  # Check if any instance matching the subquery transitively reaches this instance
  def reached_by_subquery_transitively?(instance, subquery_target, visited, depth, max_depth, _unused = nil,
                                        verbs = nil, exclude_verbs = false)
    return false if depth >= max_depth

    key = "#{instance.class}/#{instance.name}"
    return false if visited.include?(key)

    visited.add(key)

    # Use cached subquery results - computed once before filter loop
    source_set = get_subquery_results(subquery_target)
    return false if source_set.empty?

    @database.instances.each_value do |instances_hash|
      instances_hash.each_value do |other|
        next if other == instance

        other.class.relations.each do |verb, kind_name, _|
          next unless verb_matches?(verb, verbs, exclude_verbs)

          rels = other.relations(verb, kind_name)
          next unless rels.include?(instance)

          return true if source_set.include?(other)
          return true if reached_by_subquery_transitively?(other, subquery_target, visited.dup, depth + 1,
                                                           max_depth, nil, verbs, exclude_verbs)
        end
      end
    end

    false
  end
end
