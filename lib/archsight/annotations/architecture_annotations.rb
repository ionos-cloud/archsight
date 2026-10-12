# frozen_string_literal: true

require "uri"

# Architecture module adds common architecture annotations to resource classes
module Archsight::Annotations::Architecture
  # `active` first: templates use the first value
  LIFECYCLE_STATUSES = %w[active deprecated sunset end-of-life].freeze

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
      annotation "lifecycle/status",
                 description: "Lifecycle state: active, deprecated (do not start new uses), sunset (being phased out) " \
                              "or end-of-life (no longer operated or supported)",
                 enum: LIFECYCLE_STATUSES,
                 title: "Lifecycle"
      annotation "lifecycle/deprecatedAt",
                 description: "When the resource was deprecated (ISO 8601 date or time)",
                 title: "Deprecated at",
                 validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }
      annotation "lifecycle/sunsetAt",
                 description: "When the resource goes (or went) into sunset (ISO 8601 date or time)",
                 title: "Sunset at",
                 validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }
      annotation "lifecycle/endOfLifeAt",
                 description: "When the resource reaches (or reached) end-of-life (ISO 8601 date or time)",
                 title: "End of life at",
                 validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }
      annotation "lifecycle/replacedBy",
                 description: "The resource that replaces this one: a name for the same kind, Kind/Name for another (a component can be replaced by an ApplicationService/...)",
                 title: "Replaced by",
                 type: Archsight::Annotations::ResourceReference
      annotation "lifecycle/reason",
                 description: "Why the resource is deprecated",
                 title: "Reason",
                 format: :markdown
    end
  end
end
