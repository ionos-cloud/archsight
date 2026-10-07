# frozen_string_literal: true

require "fast_mcp"
require_relative "../database"
require_relative "../resources"

# Shared database and helper methods for MCP tools
module Archsight::MCP
  class << self
    attr_accessor :db

    def complete_summary(resource, omit_kind: false)
      result = {
        name: resource.name,
        metadata: {
          annotations: resource.annotations
        },
        spec: resource.spec
      }
      result[:kind] = resource.class.to_s.split("::").last unless omit_kind
      result
    end

    def brief_summary(resource, omit_kind: false)
      result = { name: resource.name }
      result[:kind] = resource.class.to_s.split("::").last unless omit_kind
      result
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
