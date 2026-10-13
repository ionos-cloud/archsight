# frozen_string_literal: true

# Facility represents a building, data center or site
class Archsight::Resources::Facility < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a physical structure where technology runs: a building, data center or other site.

    ## ArchiMate Definition

    **Layer:** Physical
    **Aspect:** Active Structure

    A facility is a physical structure or environment. Technology nodes, services and system software are located
    at facilities, and facilities themselves are located at a place.

    ## Usage

    Use Facility to represent:

    - Data centers and colocation sites
    - Offices
    - Edge sites
    - Parts of a site (campus, building, hall), nested with `composedOf`

    ## Not this kind

    - A country, metro or region is a `Location`
    - A rack, cage or fabric inside the site is `Equipment`; a server is a `TechnologyNode` `locatedAt` the facility
    - A data center is never a `TechnologyNode` and never an annotation on other elements

    Which kind to pick: "Choosing the Kind: Infrastructure" in the modeling guide.

    ## How it connects

    - Things that run at a facility point to it with `locatedAt`: `TechnologyNode`, `TechnologyService`,
      `TechnologySystemSoftware` and `Equipment`. One element can be located at many facilities (one cluster that
      runs in three data centers is one element with three relations, not three copies)
    - A facility is `locatedAt` a `Location` and `composedOf` other facilities (campus, hall)
    - A facility is `servedBy` the `BusinessActor` that operates it
    - The facility page lists what is located there (incoming `locatedAt`), grouped by kind

    A service that runs on different platforms in different facilities is not given a qualifier: the nodes of the
    platform are `locatedAt` the same facilities, so the pair is derivable.
  MD

  icon "building"
  layer "physical"

  annotation "facility/type",
             description: "Kind of site",
             title: "Facility Type",
             enum: %w[data-center colocation office edge],
             filter: :word,
             summary: true

  annotation "facility/stage",
             description: "Free text stage of the facility (planned, in build, productive, phase-out, ...)",
             title: "Stage",
             filter: :word,
             summary: true

  relation :locatedAt, :locations, :Location
  relation :composedOf, :facilities, :Facility
  relation :servedBy, :businessActors, :BusinessActor
end
