# frozen_string_literal: true

# Location represents a geographic or conceptual place
class Archsight::Resources::Location < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a place: a country, a metro area, a region or any other geographic or conceptual position.

    ## ArchiMate Definition

    **Layer:** Physical (ArchiMate: composite element)
    **Aspect:** Composite

    A location is a conceptual or physical place or position where concepts are located (structure elements)
    or performed (behavior elements). In archsight it is the coarse place that facilities sit in.

    ## Usage

    Use Location to represent:

    - Countries and regions (Germany, EU)
    - Metro areas and cities (Frankfurt)
    - Conceptual places (a cloud region, a jurisdiction)

    ## Not this kind

    - A building, campus or hall is a `Facility` that is `locatedAt` the location
    - A cloud region that is really a set of data centers: a location, with the data centers as facilities in it

    Which kind to pick: "Choosing the Kind: Infrastructure" in the modeling guide.

    ## How it connects

    - A `Facility` is `locatedAt` a location (many facilities, one location)
    - Everything located at a facility of the location is found through the facility; the location page lists the
      facilities that are located there, grouped by kind

    Model the sites themselves as `Facility`, not as locations: a data center is a physical structure.
  MD

  icon "map-pin"
  layer "physical"

  annotation "location/country",
             description: "Country of the location (name or ISO 3166 code)",
             title: "Country",
             filter: :word,
             summary: true

  annotation "location/city",
             description: "City or metro area of the location",
             title: "City",
             filter: :word,
             summary: true
end
