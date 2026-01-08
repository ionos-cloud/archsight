# frozen_string_literal: true

require "kramdown"

module Archsight
  class Linter
    # Available view components (partials in views/partials/components/)
    VALID_COMPONENTS = %w[activity git jira languages owner repositories status].freeze

    def initialize(database)
      @database = database
      @errors = []
    end

    def validate
      @database.instances.each_value do |instances_hash|
        instances_hash.each_value do |instance|
          validate_instance_annotations(instance)
          validate_view_fields(instance) if instance.klass == "View"
        end
      end

      @errors
    end

    private

    def validate_instance_annotations(instance)
      instance.annotations.each do |key, value|
        # Find matching annotation definition (handles both exact and pattern matches)
        annotation = instance.class.annotation_matching(key)

        if annotation.nil?
          @errors << "#{instance.path_ref}: Unknown annotation '#{key}' for #{instance.klass}"
          next
        end

        # Skip validation if annotation has no constraints (enum or type)
        next unless annotation.has_validation?

        # Validate value against annotation schema (type and enum constraints)
        annotation.validate(value).each do |error|
          @errors << "#{instance.path_ref}: Annotation '#{key}' #{error}"
        end

        # Check markdown syntax
        validate_markdown(instance, key, value) if annotation.markdown?
      end
    end

    def validate_markdown(instance, key, value)
      # Skip markdown validation for generated files
      return if instance.annotations.key?("generated/script")

      begin
        Kramdown::Document.new(value, input: "GFM")
      rescue StandardError => e
        @errors << "#{instance.path_ref}: Markdown syntax error in annotation '#{key}': #{e.message}"
      end
    end

    def validate_view_fields(instance)
      fields = instance.annotations["view/fields"]
      return unless fields

      fields.split(",").map(&:strip).each do |field|
        next unless field.start_with?("@")

        component_name = field[1..]
        unless VALID_COMPONENTS.include?(component_name)
          @errors << "#{instance.path_ref}: Unknown view component '@#{component_name}'. " \
                     "Valid components: #{VALID_COMPONENTS.map { |c| "@#{c}" }.join(", ")}"
        end
      end
    end
  end
end
