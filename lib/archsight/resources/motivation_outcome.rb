# frozen_string_literal: true

# MotivationOutcome represents an end result, effect, or consequence of a certain state of affairs
# (ArchiMate Motivation Layer)
class Archsight::Resources::MotivationOutcome < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents an end result that has been achieved or is intended to be achieved.

    ## ArchiMate Definition

    **Layer:** Motivation
    **Aspect:** Passive Structure

    An outcome represents an end result that has been achieved. Outcomes are measurable
    results that indicate whether goals have been reached, providing concrete evidence
    of progress or success.

    ## Usage

    Use MotivationOutcome to represent:

    - Achieved milestones
    - Measurable results
    - Key performance indicators (KPIs)
    - Success criteria
    - Deliverables
  MD

  icon "badge-check"
  layer "motivation"
end
