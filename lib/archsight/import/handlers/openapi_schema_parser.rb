# frozen_string_literal: true

require "archsight/import"
require "dry/inflector"

# Parses OpenAPI schemas and extracts DataObject information
#
# Features:
# - Schema name normalization (strips CRUD prefixes/suffixes, singularizes)
# - Skip utility schemas (Error, Links, Metadata, etc.)
# - $ref resolution with cycle detection
# - allOf composition handling
# - Nested property extraction (up to 3 levels deep)
# - Field documentation generation (markdown table format)
class Archsight::Import::Handlers::OpenAPISchemaParser
  # Schemas that should be skipped (utility schemas)
  SKIP_SCHEMAS = %w[
    Error Links Offset Limit Metadata PaginationLinks ErrorMessage Pagination
    ErrorMessages Type State ErrorResponse ValidationError InternalError
    NotFoundError ForbiddenError UnauthorizedError BadRequestError
    ConflictError RateLimitError ServiceUnavailableError
  ].freeze

  # Suffixes to strip from schema names for normalization
  STRIP_SUFFIXES = %w[
    Create Read Ensure ReadList List Patch Update Put Post Response Request
    Properties Resource Item Items Collection Result Results Output Input
    Dto DTO Entity Model Data Info Details Summary Overview
  ].freeze

  # Prefixes to strip from schema names for normalization
  STRIP_PREFIXES = %w[
    Create Get Update Delete Set Add Remove List Fetch Patch
  ].freeze

  # Words that should remain plural (don't singularize)
  KEEP_PLURAL = %w[
    Status Address Class Process Access Alias Analysis Basis
    Canvas Census Chorus Circus Corpus Crisis Diagnosis Ellipsis
    Emphasis Genesis Hypothesis Oasis Paralysis Parenthesis Synopsis
    Thesis Axis Redis Kubernetes
  ].freeze

  # Maximum depth for nested property extraction
  MAX_PROPERTY_DEPTH = 3

  attr_reader :schemas, :parsed_objects

  # @param openapi_doc [Hash] Parsed OpenAPI document
  def initialize(openapi_doc)
    @openapi_doc = openapi_doc
    @schemas = openapi_doc.dig("components", "schemas") || {}
    @parsed_objects = {}
    @visited_refs = Set.new
    @inflector = Dry::Inflector.new
  end

  # Parse all schemas and return normalized DataObjects
  # @return [Hash<String, Hash>] Map of normalized name to data object info
  def parse
    # First pass: create entries for each unique normalized name
    @schemas.each_key do |schema_name|
      next if skip_schema?(schema_name)

      normalized_name = normalize_name(schema_name)
      next if normalized_name.empty?
      next if @parsed_objects.key?(normalized_name)

      schema = @schemas[schema_name]
      @visited_refs.clear

      properties = extract_properties(schema, depth: 0)
      next if properties.empty? && !has_schema_content?(schema)

      @parsed_objects[normalized_name] = {
        "original_names" => [schema_name],
        "properties" => properties,
        "description" => schema["description"]
      }
    end

    # Second pass: track all original names that map to each normalized name
    # rubocop:disable Style/CombinableLoops -- loops must be separate: first creates entries, second merges
    @schemas.each_key do |schema_name|
      next if skip_schema?(schema_name)

      normalized_name = normalize_name(schema_name)
      next if normalized_name.empty?
      next unless @parsed_objects.key?(normalized_name)

      original_names = @parsed_objects[normalized_name]["original_names"]
      original_names << schema_name unless original_names.include?(schema_name)
    end
    # rubocop:enable Style/CombinableLoops

    @parsed_objects
  end

  # Generate markdown documentation for properties
  # @param properties [Array<Hash>] Property list
  # @return [String] Markdown table
  def self.generate_field_docs(properties)
    return "" if properties.empty?

    lines = ["## Fields", "", "| Field | Type | Required | Description |", "|-------|------|----------|-------------|"]

    properties.each do |prop|
      name = "`#{prop["name"]}`"
      type = prop["type"] || "object"
      type = "#{type} (#{prop["format"]})" if prop["format"]
      required = prop["required"] ? "Yes" : "No"
      description = (prop["description"] || "").gsub(/\s+/, " ").strip

      # Truncate long descriptions
      description = "#{description[0, 80]}..." if description.length > 80

      lines << "| #{name} | #{type} | #{required} | #{description} |"
    end

    lines.join("\n")
  end

  private

  # Check if schema should be skipped
  # @param name [String] Schema name
  # @return [Boolean]
  def skip_schema?(name)
    SKIP_SCHEMAS.any? { |skip| name == skip || name.end_with?(skip) }
  end

  # Check if schema has meaningful content (properties, refs, composition)
  # @param schema [Hash] Schema definition
  # @return [Boolean]
  def has_schema_content?(schema)
    return false if schema.nil?

    schema["properties"] || schema["$ref"] || schema["allOf"] ||
      schema["oneOf"] || schema["anyOf"] || schema["type"] == "object"
  end

  # Normalize schema name by removing CRUD prefixes/suffixes and singularizing
  # @param name [String] Original schema name
  # @return [String] Normalized name
  def normalize_name(name)
    result = name.dup

    # Strip prefixes only if followed by an uppercase letter (word boundary)
    STRIP_PREFIXES.each do |prefix|
      if result.start_with?(prefix) && result.length > prefix.length
        next_char = result[prefix.length]
        result = result.sub(/^#{prefix}/, "") if next_char == next_char.upcase && next_char =~ /[A-Z]/
      end
    end

    # Strip suffixes (can apply multiple times for compound suffixes like CreateResponse)
    2.times do
      STRIP_SUFFIXES.each do |suffix|
        result = result[0..-(suffix.length + 1)] if result.end_with?(suffix) && result.length > suffix.length
      end
    end

    # Singularize unless in keep_plural list
    result = @inflector.singularize(result) unless KEEP_PLURAL.any? { |word| result.downcase == word.downcase }

    result
  end

  # Extract properties from a schema
  # @param schema [Hash] Schema definition
  # @param depth [Integer] Current depth for nested extraction
  # @param prefix [String] Property name prefix for nested properties
  # @return [Array<Hash>] List of property definitions
  def extract_properties(schema, depth:, prefix: "")
    return [] if schema.nil? || depth > MAX_PROPERTY_DEPTH

    # Handle special schema types first
    result = extract_special_schema(schema, depth: depth, prefix: prefix)
    return result if result

    # Handle object properties
    extract_object_properties(schema, depth: depth, prefix: prefix)
  end

  # Extract from $ref, allOf, oneOf, or anyOf schemas
  def extract_special_schema(schema, depth:, prefix:)
    return resolve_ref(schema["$ref"], depth: depth, prefix: prefix) if schema["$ref"]
    return schema["allOf"].flat_map { |sub| extract_properties(sub, depth: depth, prefix: prefix) } if schema["allOf"]

    return unless schema["oneOf"] || schema["anyOf"]

    options = schema["oneOf"] || schema["anyOf"]
    extract_properties(options.first, depth: depth, prefix: prefix) if options.any?
  end

  # Extract properties from an object schema
  def extract_object_properties(schema, depth:, prefix:)
    properties = schema["properties"] || {}
    required_props = schema["required"] || []

    properties.flat_map do |prop_name, prop_schema|
      full_name = prefix.empty? ? prop_name : "#{prefix}.#{prop_name}"
      extract_single_property(prop_schema, full_name, required_props.include?(prop_name), depth)
    end
  end

  # Extract a single property, handling nested objects and arrays
  def extract_single_property(prop_schema, full_name, required, depth)
    if nested_object?(prop_schema)
      extract_nested_property(prop_schema, full_name, required, depth)
    elsif array_of_refs?(prop_schema)
      [build_array_property(prop_schema, full_name, required)]
    else
      [build_simple_property(prop_schema, full_name, required)]
    end
  end

  def nested_object?(prop_schema)
    prop_schema["$ref"] || prop_schema["type"] == "object" || prop_schema["allOf"]
  end

  def array_of_refs?(prop_schema)
    prop_schema["type"] == "array" && prop_schema.dig("items", "$ref")
  end

  def extract_nested_property(prop_schema, full_name, required, depth)
    nested = extract_properties(prop_schema, depth: depth + 1, prefix: full_name)
    if nested.empty? && prop_schema["type"] == "object"
      [{ "name" => full_name, "type" => "object", "required" => required, "description" => prop_schema["description"] }]
    else
      nested
    end
  end

  def build_array_property(prop_schema, full_name, required)
    {
      "name" => full_name, "type" => "array",
      "format" => extract_ref_name(prop_schema.dig("items", "$ref")),
      "required" => required, "description" => prop_schema["description"]
    }
  end

  def build_simple_property(prop_schema, full_name, required)
    {
      "name" => full_name, "type" => prop_schema["type"] || "string",
      "format" => prop_schema["format"], "required" => required, "description" => prop_schema["description"]
    }
  end

  # Resolve a $ref and extract its properties
  # @param ref [String] Reference string (e.g., "#/components/schemas/Server")
  # @param depth [Integer] Current depth
  # @param prefix [String] Property name prefix
  # @return [Array<Hash>] List of property definitions
  def resolve_ref(ref, depth:, prefix: "")
    # Cycle detection
    return [] if @visited_refs.include?(ref)

    @visited_refs.add(ref)

    # Parse local reference
    if ref.start_with?("#/components/schemas/")
      schema_name = ref.sub("#/components/schemas/", "")
      schema = @schemas[schema_name]
      return extract_properties(schema, depth: depth, prefix: prefix) if schema
    end

    []
  end

  # Extract schema name from a $ref
  # @param ref [String] Reference string
  # @return [String, nil] Schema name or nil
  def extract_ref_name(ref)
    return nil unless ref

    ref.sub("#/components/schemas/", "")
  end
end
