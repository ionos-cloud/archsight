# frozen_string_literal: true

# MotivationStakeholder represents the role of an individual, team, or organization
# that represents their interests in the effects of the architecture (ArchiMate Motivation Layer)
class Archsight::Resources::MotivationStakeholder < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents the interest of an individual, team, or organization in the architecture.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Active Structure

    A stakeholder represents the role of an individual, team, or organization that
    represents their interests in the effects of the architecture. Stakeholders have
    concerns about capabilities, requirements, and constraints.

    ## Usage

    Use MotivationStakeholder to represent:

    - Product owners
    - Executive sponsors
    - Customer representatives
    - Regulatory bodies
    - Technical leadership

    ## How it connects

    - It `hasConcern` for the capabilities, goals, drivers, assessments, constraints and requirements it cares about.
      That makes it the **source** of those requirements: the requirement's page shows the stakeholder as incoming.
    - It is `representedBy` the `BusinessActor` (the actual organisation or person, e.g. the customer organisation,
      not "customer") or `BusinessRole` that holds this interest. A stakeholder is a role; the actor is the party
      behind it.

    In ArchiMate a stakeholder is associated with the business actor or role that plays it; in TOGAF the stakeholder
    map of Phase A links stakeholders and their concerns to organisation units and actors, and the requirements
    repository records each requirement's source.

    ## Security and risk modelling

    A stakeholder (CISO, risk committee, data protection officer) can `hasConcern` for threats
    (`MotivationDriver`) and risks (`MotivationAssessment`) in addition to goals and requirements.
  MD

  icon "user-crown"
  layer "motivation"

  relation :hasConcern, :strategyCapabilities, :StrategyCapability
  relation :hasConcern, :motivationRequirements, :MotivationRequirement
  relation :hasConcern, :motivationConstraints, :MotivationConstraint
  relation :hasConcern, :goals, :MotivationGoal
  relation :hasConcern, :motivationDrivers, :MotivationDriver
  relation :hasConcern, :motivationAssessments, :MotivationAssessment
  relation :representedBy, :businessActors, :BusinessActor
  relation :representedBy, :businessRoles, :BusinessRole
end
