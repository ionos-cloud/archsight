# frozen_string_literal: true

require_relative "base"

class Archsight::MCP::ResourceDocTool < FastMcp::Tool
  tool_name "resource_doc"

  description <<~DESC.gsub("\n", " ").strip
    Get documentation for architecture resource kinds.

    TWO MODES OF OPERATION:

    1. LIST MODE (no kind specified): Returns a list of all available resource kinds with their descriptions.
       Useful for discovering what types of resources exist in the architecture model.
       Example: call with no parameters

    2. DOCUMENTATION MODE (kind specified): Returns detailed documentation for a specific resource kind.
       Includes description, available annotations, relations, and a YAML example template.
       Example: kind="TechnologyArtifact"

    COMMON RESOURCE KINDS:
    • TechnologyArtifact - Code repositories, artifacts, and technology components
    • ApplicationComponent - Services and application building blocks
    • ApplicationInterface - APIs and interfaces exposed by components
    • ApplicationService - Business services provided by applications
    • BusinessRequirement - Compliance controls and business requirements
    • ComplianceEvidence - Evidence linking artifacts to compliance requirements
  DESC
  arguments do
    optional(:kind).filled(:string).description(
      'Resource kind to get documentation for (e.g., "TechnologyArtifact", "ApplicationComponent"). ' \
      "If not specified, returns a list of all available resource kinds."
    )
  end

  def call(kind: nil)
    if kind.nil? || kind.empty?
      list_resource_kinds
    else
      get_resource_documentation(kind)
    end
  rescue StandardError => e
    error_response(e.message, e.class.name)
  end

  private

  def error_response(message, error_type = "Error")
    JSON.pretty_generate({
                           error: error_type,
                           message: message
                         })
  end

  def list_resource_kinds
    kinds = []

    Archsight::Resources.each do |kind_symbol|
      klass = Archsight::Resources.const_get(kind_symbol)
      kinds << {
        kind: kind_symbol.to_s,
        description: klass.description || "No description available",
        annotation_count: klass.annotations.count,
        relation_count: klass.relations.count
      }
    end

    result = {
      total: kinds.length,
      resource_kinds: kinds
    }

    JSON.pretty_generate(result)
  end

  def get_resource_documentation(kind)
    klass = Archsight::Resources[kind]
    return error_response("Unknown resource kind: #{kind}") unless klass

    content = Archsight::Documentation.generate(kind)

    JSON.pretty_generate({
                           kind: kind,
                           documentation: content
                         })
  end
end
