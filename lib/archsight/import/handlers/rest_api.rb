# frozen_string_literal: true

require "fileutils"
require "net/http"
require "yaml"
require "uri"
require "openssl"
require_relative "../handler"
require_relative "../registry"
require_relative "openapi_schema_parser"

# REST API handler - downloads OpenAPI spec and generates ApplicationInterface and DataObject resources
#
# Configuration (passed from rest_api_index handler):
#   import/config/name - API name (e.g., "compute")
#   import/config/version - API version (e.g., "6.0")
#   import/config/visibility - API visibility (e.g., "private")
#   import/config/specUrl - Full URL to OpenAPI spec (http, https, or file://)
#   import/config/htmlUrl - Full URL to HTML documentation (optional)
#   import/config/gate - Release gate (e.g., "GA", "BETA")
#   import/config/interfaceOutputPath - Output path for ApplicationInterface resources
#   import/config/dataObjectOutputPath - Output path for DataObject resources
#
# Output:
#   - ApplicationInterface resource with annotations
#   - DataObject resources extracted from OpenAPI schemas
class Archsight::Import::Handlers::RestApi < Archsight::Import::Handler
  def execute
    @name = config("name")
    raise "Missing required config: name" unless @name

    @version = config("version", default: "1.0")
    @visibility = config("visibility", default: "private")
    @spec_url = config("specUrl")
    raise "Missing required config: specUrl" unless @spec_url

    @html_url = config("htmlUrl")
    @gate = config("gate", default: "GA")

    @interface_output_path = config("interfaceOutputPath")
    @data_object_output_path = config("dataObjectOutputPath")

    # Download and parse OpenAPI spec
    progress.update("Downloading OpenAPI spec for #{@name}")
    openapi_doc = fetch_openapi_spec(@spec_url)

    # Parse schemas and generate DataObjects first (needed for interface relations)
    progress.update("Extracting DataObjects from #{@name} schemas")
    parser = Archsight::Import::Handlers::OpenAPISchemaParser.new(openapi_doc)
    parsed_objects = parser.parse
    data_objects = generate_data_objects(parsed_objects)

    # Generate ApplicationInterface with references to DataObjects
    progress.update("Generating ApplicationInterface for #{@name}")
    data_object_names = data_objects.map { |obj| obj.dig("metadata", "name") }
    interface_resource = generate_interface(openapi_doc, data_object_names: data_object_names)

    # Write outputs
    if @interface_output_path
      write_yaml(YAML.dump(interface_resource), filename: nil, sort_key: "#{@name}-interface")
    else
      write_yaml(YAML.dump(interface_resource), filename: "#{safe_api_name}-interface.yaml")
    end

    if data_objects.any?
      data_yaml = data_objects.map { |r| YAML.dump(r) }.join("\n")
      if @data_object_output_path
        # Use shared output path - write each object with a sort key
        data_objects.each do |obj|
          write_data_object(obj)
        end
      else
        write_yaml(data_yaml, filename: "#{safe_api_name}-data-objects.yaml")
      end
    end

    progress.update("Generated #{data_objects.size} DataObjects for #{@name}")

    write_generates_meta
  end

  private

  def safe_api_name
    @name.gsub(/[^a-zA-Z0-9_-]/, "_").downcase
  end

  def fetch_openapi_spec(url)
    uri = URI(url)

    case uri.scheme
    when "file"
      fetch_file_spec(uri)
    when "http", "https"
      fetch_http_spec(uri)
    else
      raise "Unsupported URL scheme: #{uri.scheme}. Use http://, https://, or file://"
    end
  end

  def fetch_file_spec(uri)
    # Handle file:// URLs - the host part may be treated as part of the path
    # e.g., file://lib/path becomes host=lib, path=/path
    # We need to reconstruct: host + path
    path = if uri.host && uri.host != "localhost" && !uri.host.empty?
             "#{uri.host}#{uri.path}"
           else
             uri.path
           end

    raise "File not found: #{path}" unless File.exist?(path)

    content = File.read(path)
    parse_spec_content(content)
  end

  def fetch_http_spec(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 30
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/yaml, application/json"

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      parse_spec_content(response.body)
    when Net::HTTPRedirection
      # Follow redirect
      fetch_openapi_spec(response["location"])
    else
      raise "Failed to fetch OpenAPI spec from #{uri}: #{response.code} #{response.message}"
    end
  end

  def parse_spec_content(content)
    # Try YAML first, then JSON
    YAML.safe_load(content, permitted_classes: [Date, Time])
  rescue Psych::SyntaxError
    JSON.parse(content)
  end

  def generate_interface(openapi_doc, data_object_names: [])
    info = openapi_doc["info"] || {}
    title = info["title"] || @name.capitalize
    description = info["description"] || ""
    openapi_version = openapi_doc["openapi"] || "3.0.0"

    # Detect technologies from spec
    tags = detect_technologies(openapi_doc)

    # Build resource name
    interface_name = build_interface_name

    annotations = {
      "architecture/title" => title,
      "architecture/description" => description.strip,
      "architecture/openapi" => openapi_version,
      "architecture/version" => @version,
      "architecture/status" => @gate,
      "architecture/visibility" => @visibility,
      "architecture/tags" => tags.join(","),
      "architecture/encoding" => "json"
    }
    annotations["architecture/documentation"] = @html_url if @html_url

    # Build spec with technology relations and data objects
    spec = {
      "servedBy" => {
        "technologyComponents" => build_technology_components(tags)
      }
    }

    # Add relation to DataObjects if any were generated
    spec["serves"] = { "dataObjects" => data_object_names } if data_object_names.any?

    resource_yaml(
      kind: "ApplicationInterface",
      name: interface_name,
      annotations: annotations,
      spec: spec
    )
  end

  def build_interface_name
    visibility_prefix = @visibility.split("-").map(&:capitalize).join
    api_name = @name.split(/[-_]/).map(&:capitalize).join
    # Handle version that may already have "v" prefix (e.g., "v1" or "1.0")
    version_str = @version.split(".").first
    version_str = version_str.sub(/^v/i, "") # Remove leading v if present
    "#{visibility_prefix}:#{api_name}:v#{version_str}:RestAPI"
  end

  def detect_technologies(openapi_doc)
    tags = %w[https rest]

    # Check security schemes
    security_schemes = openapi_doc.dig("components", "securitySchemes") || {}

    security_schemes.each_value do |scheme|
      case scheme["type"]
      when "http"
        case scheme["scheme"]&.downcase
        when "bearer"
          tags << "jwt" if scheme["bearerFormat"]&.downcase == "jwt"
          tags << "bearer" unless tags.include?("jwt")
        when "basic"
          tags << "basic-auth"
        end
      when "apiKey"
        tags << "api-key"
      when "oauth2"
        tags << "oauth2"
      when "openIdConnect"
        tags << "oidc"
      end
    end

    # Check for specific headers or patterns
    tags << "auth" if openapi_doc["paths"]&.to_s&.include?("Authorization") && tags.none? { |t| t.include?("auth") || t == "jwt" || t == "bearer" }

    tags.uniq
  end

  def build_technology_components(tags)
    components = ["HTTPS:REST"]

    tags.each do |tag|
      case tag
      when "jwt"
        components << "AUTH:JWT"
      when "basic-auth"
        components << "AUTH:Basic"
      when "api-key"
        components << "AUTH:APIKey"
      when "oauth2"
        components << "AUTH:OAuth2"
      when "oidc"
        components << "AUTH:OIDC"
      end
    end

    components.uniq
  end

  def generate_data_objects(parsed_objects)
    app_name = @name.split(/[-_]/).map(&:capitalize).join

    parsed_objects.map do |normalized_name, info|
      object_name = "#{app_name}:#{normalized_name}"

      # Build description with field documentation
      description_parts = []
      description_parts << info["description"] if info["description"]

      if info["properties"]&.any?
        field_docs = Archsight::Import::Handlers::OpenAPISchemaParser.generate_field_docs(info["properties"])
        description_parts << field_docs unless field_docs.empty?
      end

      annotations = {
        "data/application" => app_name,
        "data/visibility" => @visibility,
        "architecture/description" => description_parts.join("\n\n"),
        "generated/variants" => info["original_names"].join(", ")
      }

      resource_yaml(
        kind: "DataObject",
        name: object_name,
        annotations: annotations,
        spec: {}
      )
    end
  end

  def write_data_object(obj)
    # Override the output path for data objects
    original_output_path = import_resource.annotations["import/outputPath"]
    import_resource.annotations["import/outputPath"] = @data_object_output_path

    name = obj.dig("metadata", "name")
    write_yaml(YAML.dump(obj), sort_key: name)

    # Restore original output path
    import_resource.annotations["import/outputPath"] = original_output_path
  end
end

Archsight::Import::Registry.register("rest-api", Archsight::Import::Handlers::RestApi)
