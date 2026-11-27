# frozen_string_literal: true

# Full-text conditions (`text: "words"`, search box words) of the Evaluator: answered by the TextIndex once per
# condition, and the relevance order of results (full-text score times the weight of the kind).
module Archsight::Query::FullText
  # What a name hit of search box words adds to the relevance of a resource (a word in the name already scores high
  # in the full-text index; this ranks names that contain a word only as part of a longer word)
  NAME_BONUS = 5.0

  # The full-text nodes that decide the order of results: not negated, not inside a sub-query
  def self.ranking_nodes(node, found = [])
    case node
    when Archsight::Query::AST::QueryNode then ranking_nodes(node.expression, found)
    when Archsight::Query::AST::BinaryOp
      ranking_nodes(node.left, found)
      ranking_nodes(node.right, found)
    when Archsight::Query::AST::SearchTerms then found << node
    when Archsight::Query::AST::TextCondition then found << node if node.fulltext?
    end
    found
  end

  # The results ordered by relevance when the query searches text (full-text conditions and search box words that are
  # not negated): weight of the kind (TextIndex::Weights) times the full-text score, best first, then by name.
  # Without such conditions the results are returned as they are.
  def rank(query_node, results)
    scored(query_node, results)&.map(&:first) || results
  end

  # [[instance, score]] best first, as #rank orders them; nil without text search conditions
  def scored(query_node, results)
    nodes = Archsight::Query::FullText.ranking_nodes(query_node.expression)
    return nil if nodes.empty?

    weights = @database.respond_to?(:search_weights) ? @database.search_weights : Archsight::TextIndex::Weights.for(@database)
    results.map { |instance| [instance, weights[instance.class] * relevance(nodes, instance)] }
           .sort_by { |instance, score| [-score, instance.name.to_s] }
  end

  private

  def relevance(nodes, instance)
    nodes.sum do |node|
      bonus = node.is_a?(Archsight::Query::AST::SearchTerms) && name_matches_words?(node, instance) ? NAME_BONUS : 0.0
      fulltext_hits(node)[instance].to_f + bonus
    end
  end

  # {instance => score} of a full-text node, searched once per evaluator
  def fulltext_hits(node)
    @fulltext_cache[node] ||= Archsight::TextIndex.for(@database).search(node.fulltext_expression)
  end

  def evaluate_text_condition(node, instance)
    return Archsight::Query::TextSearch.matches?(instance, node) unless node.fulltext?

    fulltext_hits(node).key?(instance)
  end

  # Search box words: the name or an alias contains every word, or the text does
  def evaluate_search_terms(node, instance)
    name_matches_words?(node, instance) || fulltext_hits(node).key?(instance)
  end

  def name_matches_words?(node, instance)
    names = names_of(instance)
    node.name_patterns.all? { |pattern| names.any? { |name| pattern.match?(name) } }
  end
end
