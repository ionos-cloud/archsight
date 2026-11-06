# frozen_string_literal: true

require_relative "base"

# What a query result can tell about the query itself: unknown annotation keys in its filters and the direct
# relations that made a resource match a relation condition.
module Archsight::MCP::QueryHints
  class << self
    # Warnings for annotation keys in the filters of a query that no resource of the queried kind (any kind without
    # a kind prefix) has and no kind declares: such a filter silently matches nothing (or, negated, everything).
    def unknown_key_warnings(parsed_query)
      keys = annotation_keys(parsed_query.ast).uniq
      return [] if keys.empty?

      kind = parsed_query.kind_filter
      klass = kind && Archsight::Resources[kind]
      classes = klass ? [klass] : Archsight::MCP.db.instances.keys
      keys.reject { |key| known_annotation_key?(key, classes) }.map do |key|
        known = known_annotation_keys(classes)
        close = known.sort_by { |candidate| [Archsight::MCP.suggestion_rank(key.downcase, candidate.downcase, 99)&.first || 9, candidate] }.first(8)
        scope = klass ? "known keys for #{kind}" : "closest known keys over all kinds (prefix the query with a Kind: to narrow)"
        "unknown annotation key \"#{key}\"; #{scope}: #{close.join(", ")}"
      end
    end

    def annotation_keys(node, found = [])
      case node
      when Archsight::Query::AST::QueryNode then annotation_keys(node.expression, found)
      when Archsight::Query::AST::BinaryOp
        annotation_keys(node.left, found)
        annotation_keys(node.right, found)
      when Archsight::Query::AST::NotOp then annotation_keys(node.operand, found)
      when Archsight::Query::AST::AnnotationCondition, Archsight::Query::AST::AnnotationExistsCondition,
           Archsight::Query::AST::AnnotationInCondition
        found << node.path
      end
      found
    end

    def known_annotation_key?(key, classes)
      classes.any? do |klass|
        klass.annotation_matching(key) || Archsight::MCP.db.instances[klass]&.each_value&.any? { |inst| inst.annotations.key?(key) }
      end
    end

    # Declared keys (patterns like scc/language/*/loc included) and the keys resources actually carry
    def known_annotation_keys(classes)
      classes.flat_map do |klass|
        declared = klass.annotations.map(&:key)
        used = (Archsight::MCP.db.instances[klass] || {}).each_value.flat_map { |inst| inst.annotations.keys }
        declared + used
      end.uniq
    end

    # The direct relation conditions of a query (`-> Kind`, `<- "Name"`, with verb filters) that are not negated,
    # as AST nodes. Transitive, `none` and sub-query targets are left out: they have no single relation to show.
    def relation_conditions(node, found = [])
      case node
      when Archsight::Query::AST::QueryNode then relation_conditions(node.expression, found)
      when Archsight::Query::AST::BinaryOp
        relation_conditions(node.left, found)
        relation_conditions(node.right, found)
      when Archsight::Query::AST::OutgoingDirectRelation, Archsight::Query::AST::IncomingDirectRelation
        found << node if [Archsight::Query::AST::KindTarget, Archsight::Query::AST::InstanceTarget].any? { |t| node.target.is_a?(t) }
      end
      found
    end

    # The direct relations of `instance` that satisfy the given relation conditions: why a relation query matched it
    def matched_via(instance, conditions)
      relations = Archsight::MCP.direct_relations(instance)
      conditions.flat_map do |cond|
        direction = cond.is_a?(Archsight::Query::AST::OutgoingDirectRelation) ? "out" : "in"
        relations.select do |rel|
          rel[:direction] == direction && relation_target_match?(cond.target, rel) && relation_verb_match?(cond, rel)
        end
      end.uniq
    end

    def relation_target_match?(target, rel)
      if target.is_a?(Archsight::Query::AST::KindTarget)
        rel[:kind] == target.kind_name
      else
        rel[:name] == target.instance_name
      end
    end

    def relation_verb_match?(cond, rel)
      return true if cond.verbs.nil?

      cond.verbs.include?(rel[:verb]) != cond.exclude_verbs
    end
  end
end
