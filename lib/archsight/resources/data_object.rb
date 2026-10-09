# frozen_string_literal: true

# DataObject represents data structured for automated processing (ArchiMate Application Layer)
class Archsight::Resources::DataObject < Archsight::Resources::Base
  include_annotations :git, :architecture, :generated, :asset, :risk

  description <<~MD
    Represents data structured for automated processing by applications.

    ## ArchiMate Definition

    **Layer:** Application
    **Aspect:** Passive Structure

    A data object represents data structured for automated processing. Data objects are
    typically accessed and manipulated by application services and components, representing
    the information model of the system.

    ## Usage

    Use DataObject to represent:

    - API request/response schemas
    - Database entities
    - Message payloads
    - Configuration structures
    - Domain models

    ## Security and risk modelling

    Data objects carry the information assets: set `asset/value` and the protection needs
    (`asset/confidentiality`, `asset/integrity`, `asset/availability`, BSI Schutzbedarf), and `risk/domain`.
  MD

  icon "database"
  layer "application"

  annotation "data/application",
             description: "Source API/application name",
             title: "Application",
             filter: :word

  annotation "data/visibility",
             description: "API visibility level",
             title: "Visibility",
             enum: %w[public private internal],
             summary: true

  annotation "generated/variants",
             description: "OpenAPI schema variants compacted into this DataObject",
             title: "Schema Variants",
             sidebar: false

  relation :realizes, :motivationConstraints, :MotivationConstraint
end
