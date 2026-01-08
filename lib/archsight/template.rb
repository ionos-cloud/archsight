# frozen_string_literal: true

require "yaml"
require_relative "resources"

module Archsight
  # Template generates YAML templates for architecture resources
  class Template
    def self.generate(kind_name)
      klass = Archsight::Resources[kind_name.to_s]
      raise "Unknown resource kind '#{kind_name}'" unless klass

      yaml = {}
      yaml["apiVersion"] = "architecture/v1alpha1"
      yaml["kind"] = kind_name
      yaml["metadata"] = {
        "name" => "TODO"
      }

      add_annotations(yaml, klass)
      add_relations(yaml, klass)

      yaml.to_yaml
    end

    class << self
      private

      def add_annotations(yaml, klass)
        non_pattern_annotations = klass.annotations.reject(&:pattern?)
        return if non_pattern_annotations.empty?

        annotations = non_pattern_annotations.to_h { |a| [a.key, a.example_value] }
        yaml["metadata"]["annotations"] = annotations unless annotations.empty?
      end

      def add_relations(yaml, klass)
        return if klass.relations.empty?

        yaml["spec"] = {} if yaml["spec"].nil?
        klass.relations.each do |verb, relation_kind, _relation_klass|
          relation_verb = verb.to_s.delete_prefix(":")
          yaml["spec"][relation_verb] ||= {}
          yaml["spec"][relation_verb][relation_kind.to_s] = []
        end
      end
    end
  end
end
