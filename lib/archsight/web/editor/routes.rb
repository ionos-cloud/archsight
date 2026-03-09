# frozen_string_literal: true

require "sinatra/base"
require "sinatra/extension"
require_relative "../../editor"
require_relative "form_builder"
require_relative "helpers"

module Archsight
  module Web
    module Editor
      # Routes for the resource editor
      module Routes
        extend Sinatra::Extension

        helpers Archsight::Web::Editor::Helpers

        # --- HTML routes (serve Vue SPA) ---

        get "/kinds/:kind/new" do
          halt 404, "Kind not found" unless Archsight::Resources[params["kind"]]
          serve_vue
        end

        get "/kinds/:kind/instances/:name/edit" do
          halt 404, "Kind not found" unless Archsight::Resources[params["kind"]]
          halt 404, "Instance not found" unless db.instance_by_kind(params["kind"], params["name"])
          serve_vue
        end

        # Legacy POST generate routes — Vue SPA handles these now
        post("/kinds/:kind/generate") { serve_vue }
        post("/kinds/:kind/instances/:name/generate") { serve_vue }

        # --- JSON API routes ---

        get "/api/v1/editor/kinds/:kind/form" do
          content_type :json
          kind = params["kind"]
          klass = Archsight::Resources[kind]
          halt 404, JSON.generate({ error: "Kind not found" }) unless klass

          data = build_form_metadata(kind, klass)
          data[:mode] = "create"
          JSON.generate(data)
        end

        get "/api/v1/editor/kinds/:kind/instances/:name/form" do
          content_type :json
          kind = params["kind"]
          klass = Archsight::Resources[kind]
          halt 404, JSON.generate({ error: "Kind not found" }) unless klass

          instance = db.instance_by_kind(kind, params["name"])
          halt 404, JSON.generate({ error: "Instance not found" }) unless instance

          data = build_form_metadata(kind, klass)
          data[:mode] = "edit"
          data[:name] = instance.name
          data[:annotations] = instance.annotations.dup
          data[:relations] = extract_instance_relations(instance)
          data[:path_ref] = "#{instance.path_ref.path}:#{instance.path_ref.line_no}"

          original_content = Archsight::Editor::FileWriter.read_document(
            path: instance.path_ref.path, start_line: instance.path_ref.line_no
          )
          data[:content_hash] = Archsight::Editor::ContentHasher.hash(original_content)
          JSON.generate(data)
        end

        post "/api/v1/editor/kinds/:kind/generate" do
          content_type :json
          kind = params["kind"]
          halt 404, JSON.generate({ error: "Kind not found" }) unless Archsight::Resources[kind]

          body = parse_json_body
          name = (body["name"] || "").strip
          annotations = extract_annotations(body)
          relations = parse_json_relations(body["relations"] || [])

          validation = Archsight::Editor.validate(kind, name: name, annotations: annotations)
          return JSON.generate({ yaml: nil, errors: validation[:errors] }) unless validation[:valid]

          resource = Archsight::Editor.build_resource(
            kind: kind, name: name, annotations: annotations, relations: relations
          )
          JSON.generate({ yaml: Archsight::Editor.to_yaml(resource), errors: nil })
        end

        post "/api/v1/editor/kinds/:kind/instances/:name/generate" do
          content_type :json
          kind = params["kind"]
          instance_name = params["name"]
          halt 404, JSON.generate({ error: "Kind not found" }) unless Archsight::Resources[kind]

          body = parse_json_body
          name = (body["name"] || instance_name).strip
          annotations = extract_annotations(body)
          relations = parse_json_relations(body["relations"] || [])

          validation = Archsight::Editor.validate(kind, name: name, annotations: annotations)
          return JSON.generate({ yaml: nil, errors: validation[:errors] }) unless validation[:valid]

          resource = Archsight::Editor.build_resource(
            kind: kind, name: name, annotations: annotations, relations: relations
          )

          original = db.instance_by_kind(kind, instance_name)
          path_ref = original&.path_ref ? "#{original.path_ref.path}:#{original.path_ref.line_no}" : nil

          JSON.generate({
                          yaml: Archsight::Editor.to_yaml(resource), errors: nil,
                          path_ref: path_ref, content_hash: body["content_hash"]
                        })
        end

        post "/api/v1/editor/kinds/:kind/instances/:name/save" do
          content_type :json
          halt 403, JSON.generate({ success: false, error: "Inline edit is disabled. Start server with --inline-edit flag." }) unless settings.inline_edit_enabled

          body = parse_json_body
          instance = db.instance_by_kind(params["kind"], params["name"])
          halt 404, JSON.generate({ success: false, error: "Instance not found" }) unless instance

          if (conflict = validate_content_hash(instance, body["content_hash"]))
            status 409
            return JSON.generate({ success: false }.merge(conflict))
          end

          begin
            Archsight::Editor::FileWriter.replace_document(
              path: instance.path_ref.path, start_line: instance.path_ref.line_no,
              new_yaml: body["yaml"]
            )
            db.reload!
            JSON.generate({ success: true, message: "Saved to #{instance.path_ref}" })
          rescue Archsight::Editor::FileWriter::WriteError => e
            status 400
            JSON.generate({ success: false, error: e.message })
          end
        end

        get "/api/v1/editor/kinds/:kind/instances" do
          kind = params["kind"]
          halt 404, "Kind not found" unless Archsight::Resources[kind]
          content_type :json
          JSON.generate(db.instances_by_kind(kind).keys.sort)
        end

        get "/api/v1/editor/relation-kinds" do
          halt 400, "Kind and verb required" unless params["kind"] && params["verb"]
          content_type :json
          JSON.generate(Archsight::Editor.target_kinds_for_verb(params["kind"], params["verb"]))
        end

        helpers do
          def parse_json_body
            JSON.parse(request.body.read)
          rescue JSON::ParserError
            halt 400, JSON.generate({ error: "Invalid JSON" })
          end
        end
      end
    end
  end
end
