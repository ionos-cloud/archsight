# frozen_string_literal: true

# MotivationGoal represents a high-level statement of intent, direction, or desired end state
# for an organization and its stakeholders (ArchiMate Motivation Layer)
class Archsight::Resources::MotivationGoal < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents a high-level statement of intent or desired end state for the organization.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Behavior

    A goal represents a high-level statement of intent, direction, or desired end state for
    an organization and its stakeholders. Goals are typically refined into more specific
    requirements that can be implemented.

    ## Usage

    Use MotivationGoal to represent:

    - Strategic objectives
    - Business targets
    - Quality goals
    - Compliance objectives
    - Performance targets

    ## Security and risk modelling

    In the Open Group risk and security overlay a goal with `goal/type` `control-objective` states what a control
    achieves against a risk: it `mitigates` the risk (`MotivationAssessment`) and is realized by the
    requirements that are the control measures.
  MD

  icon "archery"
  layer "motivation"

  annotation "goal/type",
             description: "What kind of goal this is (specialization of the goal)",
             enum: %w[business control-objective],
             filter: :word,
             summary: true

  relation :mitigates, :motivationAssessments, :MotivationAssessment
  relation :realizes, :outcomes, :MotivationOutcome
  relation :refinedBy, :goals, :MotivationGoal
  relation :realizes, :motivationRequirements, :MotivationRequirement
end
