# frozen_string_literal: true

require "uri"

# Architecture module adds common architecture annotations to resource classes
module Archsight::Annotations::Architecture
  def self.included(base)
    base.class_eval do
      annotation "architecture/abbr",
                 description: "Abbreviation or short name",
                 title: "Abbreviation"
      annotation "architecture/description",
                 description: "Textual description of the resource",
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
      annotation "architecture/applicationSets",
                 description: "Related ArgoCD ApplicationSets",
                 title: "ApplicationSets",
                 format: :markdown
    end
  end
end
