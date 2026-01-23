# frozen_string_literal: true

require_relative "../../editor"

module Archsight
  module Web
    module Editor
      # FormBuilder generates form field metadata from annotation definitions
      class FormBuilder
        # Field represents a single form field configuration
        Field = Struct.new(:key, :title, :description, :input_type, :options, :step, :required, :code_language, keyword_init: true) do
          def select?
            input_type == :select
          end

          def textarea?
            input_type == :textarea
          end

          def code?
            input_type == :code
          end

          def number?
            input_type == :number
          end

          def url?
            input_type == :url
          end

          def text?
            input_type == :text
          end

          def list?
            input_type == :list
          end
        end

        # Build form fields for a resource kind
        # @param kind [String] Resource kind
        # @return [Array<Field>]
        def self.fields_for(kind)
          annotations = Archsight::Editor.editable_annotations(kind)

          annotations.map do |ann|
            Field.new(
              key: ann.key,
              title: ann.title,
              description: ann.description,
              input_type: determine_input_type(ann),
              options: ann.enum,
              step: determine_step(ann),
              required: false,
              code_language: ann.code_language
            )
          end
        end

        # Determine input type based on annotation properties
        # @param annotation [Archsight::Annotations::Annotation]
        # @return [Symbol]
        def self.determine_input_type(annotation)
          return :select if annotation.enum

          case annotation.type.to_s
          when "Integer", "Float"
            :number
          when "URI"
            :url
          else
            return :textarea if annotation.markdown?
            return :code if annotation.code?
            return :list if annotation.list?

            :text
          end
        end

        # Determine step attribute for number inputs
        # @param annotation [Archsight::Annotations::Annotation]
        # @return [String, nil]
        def self.determine_step(annotation)
          case annotation.type.to_s
          when "Integer"
            "1"
          when "Float"
            "0.01"
          end
        end
      end
    end
  end
end
