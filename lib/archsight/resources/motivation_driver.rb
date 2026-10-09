# frozen_string_literal: true

# MotivationDriver represents an external or internal condition that motivates the enterprise to act
class Archsight::Resources::MotivationDriver < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents an external or internal condition that motivates the enterprise to define its goals and act.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Active Structure

    A driver is something that creates, motivates and fuels the change of an organization. In the risk and
    security overlay of the Open Group paper (*Modeling Enterprise Risk Management and Security with the ArchiMate
    Language*) the general notion of a **threat** (a threatening circumstance) is a driver; opportunities,
    regulations and market forces are drivers too. Set `driver/type` to say which.

    ## Usage

    Use MotivationDriver to represent:

    - Threats ("machines may fail", "attackers target customer data")
    - Opportunities
    - Regulation and legal change
    - Market and customer demand

    ## How it connects

    - A driver `influences` the assessments (risks) it leads to and other drivers
    - A threat driver `triggers` threat or loss events
    - A `MotivationStakeholder` `hasConcern` for it
  MD

  icon "fire-flame"
  layer "motivation"

  annotation "driver/type",
             description: "What kind of driver this is (specialization of the driver)",
             enum: %w[threat opportunity regulation market internal],
             filter: :word,
             summary: true

  relation :influences, :motivationAssessments, :MotivationAssessment
  relation :influences, :motivationDrivers, :MotivationDriver
  relation :triggers, :businessEvents, :BusinessEvent
  relation :triggers, :applicationEvents, :ApplicationEvent
  relation :triggers, :technologyEvents, :TechnologyEvent
end
