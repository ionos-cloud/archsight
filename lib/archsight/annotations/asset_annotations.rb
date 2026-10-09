# frozen_string_literal: true

# Asset module adds the asset profile of an asset at risk: its value and its protection need (BSI "Schutzbedarf")
module Archsight::Annotations::Asset
  NEED = %w[normal high very-high].freeze

  def self.included(base)
    base.class_eval do
      annotation "asset/value",
                 description: "Value of the asset to the organization",
                 title: "Asset value",
                 enum: %w[low medium high critical],
                 filter: :word

      annotation "asset/confidentiality",
                 description: "Protection need for confidentiality",
                 title: "Confidentiality need",
                 enum: Archsight::Annotations::Asset::NEED,
                 filter: :word

      annotation "asset/integrity",
                 description: "Protection need for integrity",
                 title: "Integrity need",
                 enum: Archsight::Annotations::Asset::NEED,
                 filter: :word

      annotation "asset/availability",
                 description: "Protection need for availability",
                 title: "Availability need",
                 enum: Archsight::Annotations::Asset::NEED,
                 filter: :word
    end
  end
end
