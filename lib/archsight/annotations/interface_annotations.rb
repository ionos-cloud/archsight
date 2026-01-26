# frozen_string_literal: true

# Interface module adds interface-specific annotations to resource classes
module Archsight::Annotations::Interface
  def self.included(base)
    base.class_eval do
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
                 description: "Lifecycle status",
                 filter: :word,
                 enum: %w[General-Availability Early-Access Development],
                 title: "Status"
      annotation "architecture/visibility",
                 description: "API visibility (public, private, internal)",
                 filter: :word,
                 enum: %w[public private internal],
                 title: "Visibility"
    end
  end
end
