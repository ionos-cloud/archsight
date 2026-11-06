# frozen_string_literal: true

require "fast_mcp"
require_relative "../database"
require_relative "../resources"

# Shared database and helper methods for MCP tools
module Archsight::MCP
  # Size budget of a tool response (characters of JSON). Larger results are cut down, with a pointer on how to
  # narrow the request, because an agent cannot read a payload this size anyway.
  MAX_RESPONSE_CHARS = 100_000

  class << self
    attr_accessor :db

    # Pretty JSON of `result`; when it exceeds the budget, `shrink` (called with the attempt number, 1, 2, ...) must
    # return a smaller result. Gives up after a few attempts with the last, smallest one.
    def fit(result, max_chars: MAX_RESPONSE_CHARS, attempts: 8)
      json = JSON.pretty_generate(result)
      attempt = 0
      while json.length > max_chars && attempt < attempts
        attempt += 1
        result = yield(attempt)
        json = JSON.pretty_generate(result)
      end
      json
    end

    # The first sentence or line of a (markdown) description, at most `max` characters
    def one_liner(text, max: 140)
      line = text.to_s.strip.split(/\n\s*\n|\n/).first.to_s.strip
      line = line[/\A.+?[.!?](?=\s|\z)/m] || line
      line.length > max ? "#{line[0, max - 1].rstrip}…" : line
    end

    # `complete_summary` reduced to the given annotation keys and relation verbs (nil = everything)
    def project(summary, fields)
      return summary if fields.nil? || fields.empty?

      wanted = fields.map(&:to_s)
      summary = summary.dup
      summary[:metadata] = { annotations: summary[:metadata][:annotations].slice(*wanted) } if summary[:metadata]
      summary[:spec] = summary[:spec].select { |verb, _| wanted.include?(verb.to_s) } if summary[:spec]
      summary
    end

    def complete_summary(resource, omit_kind: false, with_source: false)
      result = {
        name: resource.name,
        metadata: {
          annotations: resource.annotations
        },
        spec: resource.spec
      }
      result[:kind] = resource.class.to_s.split("::").last unless omit_kind
      with_source ? result.merge(source_info(resource)) : result
    end

    def brief_summary(resource, omit_kind: false, with_source: false)
      result = { name: resource.name }
      result[:kind] = kind_of(resource) unless omit_kind
      with_source ? result.merge(source_info(resource)) : result
    end

    # Where the resource is defined: `source` ("path:line", relative to the resources root), `generated`
    # (true = written by an importer, do not edit by hand) and, when several documents were merged into the
    # resource, `sources` (every contributing file, hand-written ones included).
    def source_info(resource)
      refs = resource.source_refs
      info = { source: format_ref(refs.first), generated: resource.generated? }
      info[:sources] = refs.map { |ref| format_ref(ref) } if refs.length > 1
      info
    end

    # The direct relations of a resource, both ways, as [{verb:, direction: "out"|"in", kind:, name:}]
    # ("out": the resource points at the target, "in": the other resource points at it)
    def direct_relations(instance)
      outgoing = instance.relations_grouped.flat_map do |verb, kinds|
        kinds.flat_map do |kind, targets|
          targets.map { |target| { verb: verb.to_s, direction: "out", kind: kind, name: target.name } }
        end
      end
      incoming = instance.references.map do |ref|
        { verb: ref[:verb].to_s, direction: "in", kind: kind_of(ref[:instance]), name: ref[:instance].name }
      end
      (outgoing + incoming).uniq
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
      relations = direct_relations(instance)
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

    # Up to `limit` resources whose name is close to `name`, as [{kind:, name:}]: same name in other letter case
    # first, then names containing it (or contained in it), then small edit distances. Resources of `kind` win ties.
    def suggest(name, kind: nil, limit: 5)
      wanted = name.to_s.downcase
      return [] if wanted.empty?

      threshold = [[wanted.length / 3, 2].max, 5].min
      scored = db.instances.flat_map do |klass, by_name|
        by_name.each_key.filter_map do |candidate|
          rank = suggestion_rank(wanted, candidate.to_s.downcase, threshold)
          [rank, klass.to_s.split("::").last == kind ? 0 : 1, candidate, klass.to_s.split("::").last] if rank
        end
      end
      scored.sort.first(limit).map { |(_, _, candidate, candidate_kind)| { kind: candidate_kind, name: candidate } }
    end

    def suggestion_rank(wanted, candidate, threshold)
      return [0, 0] if candidate == wanted
      return [1, (candidate.length - wanted.length).abs] if candidate.include?(wanted) || wanted.include?(candidate)

      distance = DidYouMean::Levenshtein.distance(wanted, candidate)
      [2, distance] if distance <= threshold
    end

    # "Did you mean ..." text for suggestions, or nil
    def did_you_mean(suggestions)
      return nil if suggestions.empty?

      "Did you mean: #{suggestions.map { |s| "#{s[:kind]}/#{s[:name]}" }.join(", ")}?"
    end

    # `kind`, `name`, `source` and `generated` of each direct relation target, as [{kind:, name:, source:, generated:}]
    def related_sources(instance)
      targets = instance.class.relations.flat_map do |verb, kind_name, _|
        instance.relations(verb, kind_name)
      end
      targets.uniq.map { |t| { kind: kind_of(t), name: t.name }.merge(source_info(t)) }
    end

    def format_ref(ref)
      return nil unless ref

      root = db.respond_to?(:path) ? db.path.to_s : ""
      path = ref.path.to_s
      path = path.delete_prefix(File.join(File.expand_path(root), "")) unless root.empty?
      "#{path}:#{ref.line_no}"
    end

    def annotations_summary(resource, omit_kind: false)
      result = {
        name: resource.name,
        metadata: {
          annotations: resource.annotations
        }
      }
      result[:kind] = resource.class.to_s.split("::").last unless omit_kind
      result
    end

    # The summary attributes of a resource's kind (annotations marked `summary: true`) that have a value,
    # as [{key:, title:, value:, format:, type:}]. Computed annotations are included; they are precomputed
    # at load and absent when empty. Lists (filter: :list) come back as arrays, Integer/Float typed values
    # as numbers, `type` is the short type name ("Integer", "Time", "Person", ...) or nil.
    def highlights(resource)
      resource.class.summary_annotations.filter_map do |annotation|
        value = highlight_value(annotation, resource)
        next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

        { key: annotation.key, title: annotation.title, value: value, format: annotation.format,
          type: short_type_name(annotation.type) }
      end
    end

    def extract_description(resource)
      description = resource.annotations["architecture/description"]
      return "No description" if description.nil?

      description.split("\n").first
    end

    def short_type_name(type)
      type&.name.to_s.split("::").last
    end

    # The hit's kind name ("TechnologyArtifact") and the number of hits per kind
    def kind_of(resource)
      resource.class.to_s.split("::").last
    end

    def count_by_kind(results)
      results.group_by { |r| kind_of(r) }.transform_values(&:length)
    end

    def highlight_value(annotation, resource)
      value = annotation.value_for(resource)
      return value unless value.is_a?(String)

      case annotation.type&.name
      when "Integer" then value.match?(/\A-?\d+\z/) ? value.to_i : value
      when "Float" then value.match?(/\A-?\d+(\.\d+)?\z/) ? value.to_f : value
      else value
      end
    end

    def extract_relations(instance)
      relations = {}

      instance.class.relations.each do |verb, kind_name, _|
        relations[verb] ||= {}
        relations[verb][kind_name] = instance.relations(verb, kind_name).map(&:name)
      end

      relations
    end
  end
end
