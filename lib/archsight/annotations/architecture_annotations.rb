# frozen_string_literal: true

require "uri"

# Architecture module adds common architecture annotations to resource classes
module Archsight::Annotations::Architecture
  def self.included(base)
    base.include Archsight::Annotations::Links
    base.class_eval do
      annotation "architecture/abbr",
                 description: "Abbreviation or short name",
                 title: "Abbreviation"
      annotation "architecture/description",
                 description: "Textual description of the resource",
                 title: "Description",
                 format: :markdown
      annotation "architecture/diagram",
                 description: "Diagram (.asd DSL), shown on the detail page next to the generated dependency graph",
                 title: "Diagram",
                 format: :asd
      annotation "architecture/documentation",
                 description: "Documentation URL or reference",
                 title: "Documentation",
                 type: URI
      annotation "architecture/aliases",
                 description: "Other identifiers of the resource (comma-separated), e.g. ITGS:A001; " \
                              "unique among the resources of a kind",
                 title: "Aliases",
                 filter: :list,
                 sidebar: false,
                 unique: true
      annotation "architecture/tags",
                 description: "Comma-separated tags",
                 filter: :list,
                 title: "Tags"
    end
  end
end
