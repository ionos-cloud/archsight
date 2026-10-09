# frozen_string_literal: true

# ImplementationGap represents the difference between two plateaus
class Archsight::Resources::ImplementationGap < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents a statement of difference between two plateaus.

    ## ArchiMate Definition

    **Layer:** Implementation & Migration
    **Aspect:** Passive Structure

    A gap is what is missing between a baseline and a target plateau: elements to add, change or remove. It is
    the starting point of gap analysis in the TOGAF ADM.

    ## Usage

    Use ImplementationGap to represent:

    - The difference between today's and the target architecture
    - Requirements of a standard that are not met yet (compliance gap)
    - The part of a plateau transition that a work package still has to deliver

    ## How it connects

    - A gap `compares` the plateaus it lies between (baseline and target)
    - It is `closedBy` the work packages and deliverables that remove it
  MD

  icon "git-compare"
  layer "implementation"

  annotation "gap/status",
             description: "Whether the gap is being closed",
             enum: %w[open closing closed],
             filter: :word,
             summary: true
  annotation "gap/impact",
             description: "How much the gap matters",
             enum: %w[low medium high critical],
             filter: :word,
             summary: true

  relation :compares, :implementationPlateaus, :ImplementationPlateau
  relation :closedBy, :implementationWorkPackages, :ImplementationWorkPackage
  relation :closedBy, :implementationDeliverables, :ImplementationDeliverable
end
