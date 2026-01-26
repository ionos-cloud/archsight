# frozen_string_literal: true

require "sinatra/base"
require "sinatra/extension"
require_relative "../../editor"
require_relative "form_builder"

module Archsight
  module Web
    module Editor
      # Routes for the resource editor
      module Routes
        extend Sinatra::Extension

        helpers do
          # Get form fields for a resource kind
          def editor_fields(kind)
            FormBuilder.fields_for(kind)
          end

          # Get relation verbs for a resource kind
          def relation_verbs(kind)
            Archsight::Editor.relation_verbs(kind)
          end

          # Get available relations for a resource kind
          def available_relations(kind)
            Archsight::Editor.available_relations(kind)
          end

          # Extract annotations from form params
          def extract_annotations(params)
            annotations = params["annotations"] || {}
            annotations.transform_values { |v| v.is_a?(String) ? v.strip : v }
          end

          # Extract relations from form params
          # Relations come in as arrays: verb[], kind[], name[]
          def parse_form_relations(params)
            relations = []
            relation_data = params["relations"] || []

            relation_data.each do |rel|
              next unless rel.is_a?(Hash)

              verb = rel["verb"]&.strip
              kind = rel["kind"]&.strip
              name = rel["name"]&.strip

              next if verb.nil? || verb.empty?
              next if kind.nil? || kind.empty?
              next if name.nil? || name.empty?

              # Find existing relation group or create new one
              existing = relations.find { |r| r[:verb] == verb && r[:kind] == kind }
              if existing
                existing[:names] << name unless existing[:names].include?(name)
              else
                relations << { verb: verb, kind: kind, names: [name] }
              end
            end

            relations
          end
        end

        # Create mode - empty form
        get "/kinds/:kind/new" do
          @kind = params["kind"]
          @klass = Archsight::Resources[@kind]
          halt 404, "Kind not found" unless @klass

          @editor_mode = true
          @mode = :create
          @name = ""
          @annotations = {}
          @relations = []
          @fields = editor_fields(@kind)
          @errors = {}

          haml :index
        end

        # Create mode - generate YAML
        post "/kinds/:kind/generate" do
          @kind = params["kind"]
          @klass = Archsight::Resources[@kind]
          halt 404, "Kind not found" unless @klass

          @editor_mode = true
          @mode = :create
          @name = (params["name"] || "").strip
          @annotations = extract_annotations(params)
          @relations = parse_form_relations(params)
          @fields = editor_fields(@kind)

          # Validate
          validation = Archsight::Editor.validate(@kind, name: @name, annotations: @annotations)

          unless validation[:valid]
            @errors = validation[:errors]
            return haml :index
          end

          # Build and render YAML
          resource = Archsight::Editor.build_resource(
            kind: @kind,
            name: @name,
            annotations: @annotations,
            relations: @relations
          )

          @generated_yaml = Archsight::Editor.to_yaml(resource)
          @errors = {}

          haml :index
        end

        # Edit mode - pre-filled form
        get "/kinds/:kind/instances/:name/edit" do
          @kind = params["kind"]
          @instance_name = params["name"]
          @klass = Archsight::Resources[@kind]
          halt 404, "Kind not found" unless @klass

          instance = db.instance_by_kind(@kind, @instance_name)
          halt 404, "Instance not found" unless instance

          @editor_mode = true
          @mode = :edit
          @name = instance.name
          @annotations = instance.annotations.dup
          @relations = extract_instance_relations(instance)
          @fields = editor_fields(@kind)
          @errors = {}

          haml :index
        end

        # Edit mode - generate YAML
        post "/kinds/:kind/instances/:name/generate" do
          @kind = params["kind"]
          @instance_name = params["name"]
          @klass = Archsight::Resources[@kind]
          halt 404, "Kind not found" unless @klass

          # Get original instance for path_ref (for inline save)
          original_instance = db.instance_by_kind(@kind, @instance_name)
          @path_ref = original_instance&.path_ref
          @inline_edit_enabled = settings.inline_edit_enabled

          @editor_mode = true
          @mode = :edit
          @name = (params["name_field"] || @instance_name).strip
          @annotations = extract_annotations(params)
          @relations = parse_form_relations(params)
          @fields = editor_fields(@kind)

          # Validate
          validation = Archsight::Editor.validate(@kind, name: @name, annotations: @annotations)

          unless validation[:valid]
            @errors = validation[:errors]
            return haml :index
          end

          # Build and render YAML
          resource = Archsight::Editor.build_resource(
            kind: @kind,
            name: @name,
            annotations: @annotations,
            relations: @relations
          )

          @generated_yaml = Archsight::Editor.to_yaml(resource)
          @errors = {}

          haml :index
        end

        # Save YAML to source file (inline edit)
        post "/api/v1/editor/kinds/:kind/instances/:name/save" do
          content_type :json

          # Check if inline edit is enabled
          halt 403, JSON.generate({ success: false, error: "Inline edit is disabled. Start server with --inline-edit flag." }) unless settings.inline_edit_enabled

          kind = params["kind"]
          name = params["name"]

          begin
            yaml_content = JSON.parse(request.body.read)["yaml"]
          rescue JSON::ParserError
            halt 400, JSON.generate({ success: false, error: "Invalid JSON" })
          end

          instance = db.instance_by_kind(kind, name)
          halt 404, JSON.generate({ success: false, error: "Instance not found" }) unless instance

          begin
            Archsight::Editor::FileWriter.replace_document(
              path: instance.path_ref.path,
              start_line: instance.path_ref.line_no,
              new_yaml: yaml_content
            )
            db.reload!
            JSON.generate({ success: true, message: "Saved to #{instance.path_ref}" })
          rescue Archsight::Editor::FileWriter::WriteError => e
            status 400
            JSON.generate({ success: false, error: e.message })
          end
        end

        # HTMX API - Get instance names for a kind (for relation dropdown)
        get "/api/v1/editor/kinds/:kind/instances" do
          kind = params["kind"]
          klass = Archsight::Resources[kind]
          halt 404, "Kind not found" unless klass

          instances = db.instances_by_kind(kind).keys.sort

          content_type :json
          JSON.generate(instances)
        end

        # HTMX API - Get valid target kinds for a verb
        get "/api/v1/editor/relation-kinds" do
          kind = params["kind"]
          verb = params["verb"]
          halt 400, "Kind and verb required" unless kind && verb

          target_kinds = Archsight::Editor.target_kinds_for_verb(kind, verb)

          content_type :json
          JSON.generate(target_kinds)
        end

        helpers do
          # Extract relations from an existing instance into form format
          # Returns relations with target class names (e.g., "BusinessActor")
          # not relation names (e.g., "businessActors")
          def extract_instance_relations(instance)
            relations = []

            instance.spec.each do |verb, relation_groups|
              next unless relation_groups.is_a?(Hash)

              relation_groups.each do |relation_name, targets|
                next unless targets.is_a?(Array)

                # Look up the target class name from the relation definition
                target_class = Archsight::Editor.target_class_for_relation(instance.kind, verb, relation_name)
                next unless target_class

                targets.each do |target|
                  # Target could be an instance object or a string
                  target_name = target.respond_to?(:name) ? target.name : target.to_s
                  relations << { verb: verb, kind: target_class, name: target_name }
                end
              end
            end

            relations
          end
        end
      end
    end
  end
end
