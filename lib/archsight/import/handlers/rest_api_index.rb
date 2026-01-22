# frozen_string_literal: true

require "fileutils"
require "net/http"
require "json"
require "uri"
require "openssl"
require_relative "../handler"
require_relative "../registry"

# REST API Index handler - fetches API index and generates child Import resources
#
# Configuration:
#   import/config/indexUrl - URL to fetch API index JSON (required)
#   import/config/baseUrl - Base URL for spec files (optional, derived from indexUrl)
#   import/config/interfaceOutputPath - Shared output for ApplicationInterface resources
#   import/config/dataObjectOutputPath - Shared output for DataObject resources
#   import/config/skipVisibility - Comma-separated visibilities to skip (e.g., "public-preview")
#   import/config/childCacheTime - Cache time for generated child imports (e.g., "1h", "30m")
#
# Output:
#   Generates Import:RestApi:* resources for each API in the index
#
# Expected index format (object with "pages" array):
#   {
#     "pages": [
#       {
#         "name": "compute",
#         "version": "v1",
#         "visibility": "public",
#         "spec": "/rest-api/public-compute-v1.yaml",
#         "redoc": "/rest-api/docs/compute/v1/",
#         "gate": "General-Availability"
#       },
#       ...
#     ]
#   }
class Archsight::Import::Handlers::RestApiIndex < Archsight::Import::Handler
  def execute
    @index_url = config("indexUrl")
    raise "Missing required config: indexUrl" unless @index_url

    @base_url = config("baseUrl") || derive_base_url(@index_url)
    @interface_output_path = config("interfaceOutputPath")
    @data_object_output_path = config("dataObjectOutputPath")
    @skip_visibilities = (config("skipVisibility") || "").split(",").map(&:strip).reject(&:empty?)
    @child_cache_time = config("childCacheTime")

    # Fetch API index
    progress.update("Fetching API index from #{@index_url}")
    apis = fetch_index

    if apis.empty?
      progress.warn("No APIs found in index")
      return
    end

    # Filter APIs by visibility
    original_count = apis.size
    apis = filter_apis(apis)
    progress.update("Filtered to #{apis.size} APIs (skipped #{original_count - apis.size} by visibility)") if apis.size < original_count

    # Generate child imports
    progress.update("Generating #{apis.size} import resources")
    generate_api_imports(apis)

    write_generates_meta
  end

  private

  def derive_base_url(url)
    uri = URI(url)
    "#{uri.scheme}://#{uri.host}"
  end

  def fetch_index
    uri = URI(@index_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 30
    http.read_timeout = 60

    request = Net::HTTP::Get.new(uri)
    request["Accept"] = "application/json"

    response = http.request(request)

    case response
    when Net::HTTPSuccess
      data = JSON.parse(response.body)
      # Handle both array format and object with "pages" key
      data.is_a?(Array) ? data : (data["pages"] || [])
    when Net::HTTPRedirection
      # Follow redirect
      @index_url = response["location"]
      fetch_index
    when Net::HTTPUnauthorized
      raise "API index error: 401 Unauthorized - Check credentials"
    when Net::HTTPForbidden
      raise "API index error: 403 Forbidden - Access denied"
    when Net::HTTPNotFound
      raise "API index error: 404 Not Found - Index not found at #{@index_url}"
    else
      raise "API index error: #{response.code} #{response.message}"
    end
  end

  def filter_apis(apis)
    return apis if @skip_visibilities.empty?

    apis.reject do |api|
      visibility = api["visibility"]&.downcase
      @skip_visibilities.any? { |skip| visibility == skip.downcase }
    end
  end

  def generate_api_imports(apis)
    yaml_documents = apis.map do |api|
      api_name = api["name"]
      api_version = api["version"] || "v1"

      # Build full URLs from base URL and paths
      # Support both "spec"/"redoc" (new format) and "specPath"/"redocPath" (legacy)
      spec_path = api["spec"] || api["specPath"]
      redoc_path = api["redoc"] || api["redocPath"]
      spec_url = build_full_url(spec_path)
      html_url = redoc_path ? build_full_url(redoc_path) : nil

      # Derive visibility from spec path if not explicitly provided
      visibility = api["visibility"] || derive_visibility_from_path(spec_path)

      # Include visibility in import name to distinguish public/private versions of same API
      import_name = "Import:RestApi:#{visibility}:#{api_name}:#{api_version}"
      child_config = {
        "name" => api_name,
        "version" => api["version"] || "1.0",
        "visibility" => visibility,
        "specUrl" => spec_url,
        "gate" => api["gate"] || "GA"
      }
      child_config["htmlUrl"] = html_url if html_url

      # Build annotations for child import
      child_annotations = {}
      child_annotations["import/outputPath"] = @interface_output_path if @interface_output_path
      child_annotations["import/cacheTime"] = @child_cache_time if @child_cache_time
      child_annotations["import/config/interfaceOutputPath"] = @interface_output_path if @interface_output_path
      child_annotations["import/config/dataObjectOutputPath"] = @data_object_output_path if @data_object_output_path

      import_yaml(
        name: import_name,
        handler: "rest-api",
        config: child_config,
        annotations: child_annotations
      )
    end

    # Add self-marker with generated/at for caching
    yaml_documents << self_marker

    # Write all imports to a single file
    yaml_content = yaml_documents.map { |doc| YAML.dump(doc) }.join("\n")
    write_yaml(yaml_content)
  end

  def build_full_url(path)
    return path if path.start_with?("http://", "https://", "file://")

    "#{@base_url}#{path}"
  end

  # Derive visibility from spec path patterns like "/rest-api/public-compute-v1.yaml"
  # or "/docs/public/compute/v1/"
  def derive_visibility_from_path(path)
    return "public" if path&.match?(/\bpublic\b/i)
    return "private" if path&.match?(/\bprivate\b/i)

    "public" # Default to public for APIs without explicit visibility marker
  end
end

Archsight::Import::Registry.register("rest-api-index", Archsight::Import::Handlers::RestApiIndex)
