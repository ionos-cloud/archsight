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
    • MotivationRequirement - Statements of need, such as compliance and legal requirements
    • ComplianceEvidence - Evidence linking artifacts to compliance requirements
  DESC
  arguments do
    optional(:kind).filled(:string).description(
      'Resource kind to get documentation for (e.g., "TechnologyArtifact", "ApplicationComponent"). ' \
      "If not specified, returns a compact list of all available resource kinds (one line each)."
    )
    optional(:section).filled(:string).description(
      "Only this part of a kind's documentation: 'description' (everything before the annotations), " \
      "'annotations', 'relations' or 'example'. Default: the whole document. Needs a kind."
    )
  end

  SECTIONS = %w[description annotations relations example].freeze

  def call(kind: nil, section: nil)
    if kind.nil? || kind.empty?
      list_resource_kinds
    else
      get_resource_documentation(kind, section)
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

  # One line per kind ("Kind (layer): first sentence"), so the whole list stays a few KB
  def list_resource_kinds
    kinds = []

    Archsight::Resources.each do |kind_symbol|
      klass = Archsight::Resources.const_get(kind_symbol)
      text = Archsight::MCP.one_liner(klass.description, max: 80)
      text = "No description available" if text.empty?
      kinds << "#{kind_symbol} (#{klass.layer}): #{text}"
    end

    JSON.pretty_generate({
                           total: kinds.length,
                           hint: 'Call resource_doc(kind: "<Kind>") for the full documentation, add section: ' \
                                 "description|annotations|relations|example for one part.",
                           resource_kinds: kinds
                         })
  end

  def get_resource_documentation(kind, section)
    klass = Archsight::Resources[kind]
    return error_response("Unknown resource kind: #{kind}") unless klass

    return error_response("Unknown section: #{section}. Use one of #{SECTIONS.join(", ")}") if section && !SECTIONS.include?(section)

    content = Archsight::Documentation.generate(kind)
    content = extract_section(content, section) if section
    result = { kind: kind }
    result[:section] = section if section
    result[:documentation] = content

    JSON.pretty_generate(result)
  end

  # "description" is everything before `## Annotations`; the others are the `## Name` block of that heading
  def extract_section(content, section)
    return content.split(/^## Annotations$/, 2).first.to_s.strip if section == "description"

    content[/^## #{section.capitalize}$.*?(?=^## |\z)/m].to_s.strip
  end
end
