# frozen_string_literal: true

require "uri"

# Architecture module adds common architecture annotations to resource classes
module Archsight::Annotations::Architecture
  def self.included(base)
    base.class_eval do
      annotation "architecture/abbr",
                 description: "Abbreviation or short name",
                 title: "Abbreviation"
      annotation "architecture/evidence",
                 description: "Supporting evidence or notes",
                 title: "Evidence",
                 format: :markdown
      annotation "architecture/description",
                 description: "Textual description of the interface",
                 title: "Description",
                 format: :markdown
      annotation "architecture/documentation",
                 description: "Documentation URL or reference",
                 title: "Documentation",
                 type: URI
      annotation "architecture/tags",
                 description: "Comma-separated tags",
                 filter: :list,
                 title: "Tags"
      annotation "architecture/encoding",
                 description: "Data encoding format",
                 filter: :list,
                 title: "Encoding"
      annotation "architecture/title",
                 description: "Interface title",
                 title: "Title"
      annotation "architecture/openapi",
                 description: "OpenAPI specification version",
                 filter: :word,
                 title: "OpenAPI"
      annotation "architecture/version",
                 description: "API or interface version",
                 filter: :word,
                 title: "Version",
                 sidebar: false
      annotation "architecture/status",
                 description: "Lifecycle status (General-Availability, Early-Access, Development)",
                 filter: :word,
                 title: "Status"
      annotation "architecture/visibility",
                 description: "API visibility (public, private)",
                 filter: :word,
                 enum: %w[public private],
                 title: "Visibility"
      annotation "architecture/applicationSets",
                 description: "Related ArgoCD ApplicationSets",
                 title: "ApplicationSets",
                 format: :markdown
    end
  end
end
