# frozen_string_literal: true

require "json"
require "yaml"
require_relative "resources"

module Archsight
  # The OpenAPI document of the REST API: the hand-written base (`web/api/openapi/spec.yaml`: the fixed endpoints such
  # as pages, assets, search and the editor, with their prose, examples and error shapes) plus what the model knows and
  # nobody should type twice: one schema per kind with its annotations (type, enum, description, default), its `spec`
  # relations and its relations, the list of kinds, and the instance detail schema that is one of them. A new kind, a
  # changed enum or another relation shows up in the documentation without touching the YAML.
  #
  #   Archsight::OpenAPI.document # => Hash, `.to_yaml` is what GET /api/v1/openapi.yaml serves
  module OpenAPI
    BASE = File.join(__dir__, "web", "api", "openapi", "spec.yaml")

    # The operations that answer with the detail of one instance, whose kind the path names
    DETAIL_PATHS = ["/api/v1/kinds/{kind}/instances/{name}", "/kinds/{kind}/instances/{name}.json"].freeze

    # What an annotation of a type is in the JSON. The value is the one of the YAML file, so a number may also be its
    # string ("100"); only a computed annotation is always a number. Everything else is a string.
    TYPES = {
      Integer => { "type" => %w[integer string] },
      Float => { "type" => %w[number string] }
    }.freeze

    NAMES = { "type" => "array", "items" => { "type" => "string" } }.freeze

    class << self
      # @return [Hash] the complete document; built once, the model does not change while the server runs
      def document
        @document ||= build
      end

      # Forget the built document (the model was changed, in a test)
      def reset!
        @document = nil
      end

      # The name of the schema of a kind
      def schema_name(kind) = "#{kind}Instance"

      # The schema of one kind: the detail of an instance as GET /api/v1/kinds/{kind}/instances/{name} returns it
      # @param kind [String] name of a kind
      # @return [Hash]
      def kind_schema(kind)
        klass = Archsight::Resources[kind]
        schema = {
          "type" => "object",
          "required" => %w[kind name metadata spec relations references],
          "x-layer" => klass.layer,
          "properties" => {
            "kind" => { "type" => "string", "const" => kind },
            "name" => { "type" => "string", "description" => "Name of the instance" },
            "metadata" => { "type" => "object", "properties" => { "annotations" => annotations_schema(klass) } },
            "annotation_formats" => { "type" => "object", "additionalProperties" => { "type" => "string" },
                                      "description" => "How the UI shows each annotation that is set (markdown, link, tag_list, ...)" },
            "annotation_links" => { "type" => "object", "additionalProperties" => true,
                                    "description" => "Annotations whose value names resources, with the resources they resolve to" },
            "spec" => spec_schema(klass),
            "relations" => relations_schema(klass),
            "references" => references_schema,
            "diagram" => { "type" => %w[string null], "description" => "The `architecture/diagram` annotation as inline SVG" }
          }
        }
        schema["description"] = klass.description.strip if klass.description
        schema
      end

      private

      def build
        document = YAML.safe_load_file(BASE, permitted_classes: [], aliases: true)
        kinds = Archsight::Resources.resource_classes.keys.sort
        schemas = document.fetch("components").fetch("schemas")
        add_schemas(schemas, kinds)
        document.dig("components", "parameters", "kind")["schema"] = { "$ref" => "#/components/schemas/KindName" }
        DETAIL_PATHS.each { |path| use_detail_schema(document.fetch("paths").fetch(path)) }
        # the schemas share small hashes: a copy of each keeps YAML from writing anchors and aliases for them
        JSON.parse(JSON.generate(document))
      end

      def add_schemas(schemas, kinds)
        kinds.each do |kind|
          name = schema_name(kind)
          raise ArgumentError, "OpenAPI: the schema #{name} of #{kind} clashes with a schema of the base spec" if schemas.key?(name)

          schemas[name] = kind_schema(kind)
        end
        schemas["KindName"] = {
          "type" => "string", "enum" => kinds,
          "description" => "Name of a resource kind. A kind that was renamed is still accepted under its old name."
        }
        schemas["InstanceDetail"] = {
          "description" => "An instance with its relations and references: the schema depends on the kind",
          "oneOf" => kinds.map { |kind| { "$ref" => "#/components/schemas/#{schema_name(kind)}" } },
          "discriminator" => { "propertyName" => "kind", "mapping" => kinds.to_h { |kind| [kind, "#/components/schemas/#{schema_name(kind)}"] } }
        }
      end

      def use_detail_schema(path_item)
        path_item.dig("get", "responses", "200", "content", "application/json")["schema"] = { "$ref" => "#/components/schemas/InstanceDetail" }
      end

      # The annotations of the kind that are set; every annotation is optional. Other annotations are allowed.
      def annotations_schema(klass)
        fixed, patterns = klass.annotations.partition { |annotation| !annotation.pattern? }
        schema = {
          "type" => "object", "additionalProperties" => true,
          "properties" => fixed.to_h { |annotation| [annotation.key, annotation_schema(annotation)] }
        }
        schema["patternProperties"] = patterns.to_h { |annotation| [pattern_of(annotation.key), annotation_schema(annotation)] } unless patterns.empty?
        schema
      end

      def annotation_schema(annotation)
        schema = (TYPES[annotation.type] || { "type" => "string" }).dup
        description = annotation.description.to_s.strip
        description = "#{description}\n\nRendered to HTML in the response." if annotation.format == :markdown && !description.empty?
        schema["description"] = description unless description.empty?
        if annotation.enum && annotation.list?
          # a list is one string of comma separated values, each of them one of the enum
          schema["description"] = "#{description}\n\nComma separated list of: #{annotation.enum.join(", ")}.".strip
          schema["x-items-enum"] = annotation.enum
        elsif annotation.enum
          schema["enum"] = annotation.enum
        end
        schema["default"] = annotation.default unless annotation.default.nil?
        schema["deprecated"] = true if annotation.deprecated
        schema
      end

      # `link/*` -> a regular expression for the keys it matches
      def pattern_of(key) = "^#{Regexp.escape(key).gsub('\*', ".+")}$"

      # What the file says: spec.<verb>.<key>: [names]
      def spec_schema(klass)
        properties = {}
        klass.declared_relations.each do |verb, key, target|
          verb_schema = (properties[verb.to_s] ||= { "type" => "object", "properties" => {} })
          verb_schema["properties"][key.to_s] = NAMES.merge("description" => "Names of #{target} resources")
        end
        { "type" => "object", "additionalProperties" => true, "properties" => properties,
          "description" => "The relations as written in the resource: verb, then the kind's collection, then the names" }
      end

      # The outgoing relations that exist: verb, then the kind of the target, then the names
      def relations_schema(klass)
        properties = {}
        klass.relations.each do |verb, _key, target|
          verb_schema = (properties[verb.to_s] ||= { "type" => "object" })
          if Archsight::Resources::DERIVED_VERBS.include?(verb)
            verb_schema["additionalProperties"] = NAMES # targets of any kind, grouped by the kind they are
          else
            (verb_schema["properties"] ||= {})[target.to_s] = NAMES
          end
        end
        { "type" => "object", "additionalProperties" => false, "properties" => properties,
          "description" => "Outgoing relations that have targets, grouped by verb and the kind of the target" }
      end

      def references_schema
        { "type" => "object", "additionalProperties" => { "type" => "object", "additionalProperties" => NAMES },
          "description" => "Incoming relations grouped by the kind of the source and the verb" }
      end
    end
  end
end
