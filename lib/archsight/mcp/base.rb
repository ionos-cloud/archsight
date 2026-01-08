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

    def extract_description(resource)
      description = resource.annotations["architecture/description"]
      return "No description" if description.nil?

      description.split("\n").first
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
