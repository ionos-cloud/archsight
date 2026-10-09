# frozen_string_literal: true

# ApplicationEvent represents an application event: something that happens in an application and triggers or interrupts application behavior
class Archsight::Resources::ApplicationEvent < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents an application event: something that happens in an application and triggers or interrupts application behavior.

    ## ArchiMate Definition

    **Layer:** Application
    **Aspect:** Behavior

    An event is something that happens and influences behavior. It does not last: it triggers or interrupts
    processes and services. In the risk and security overlay of the Open Group paper (*Modeling Enterprise Risk
    Management and Security with the ArchiMate Language*) a threat event and a loss event are events that carry a
    type; set `event/type` to say which.

    ## Usage

    Use ApplicationEvent for events on the application level:

    - Threat events and loss events of applications (an exploit of a service, a burst of failed logins, a data leak)
    - Security alerts raised by an application
    - Triggers of application services (a message arrives, a job is scheduled)

    ## Event types

    - `threat-event`: an event with the potential to harm an asset; it can trigger a loss event
    - `attack`: a threat event caused by intentional malicious activity
    - `loss-event`: an event that harms an asset (a hazard materialises, a vulnerability is exploited)
    - `incident`: a loss event that has happened
    - `opportunity-event`: an event that can add value
    - `audit`, `scan`, `change`: events that produce assessments or alter the architecture
    - `other`

    Filter, group and query by `event/type`, `risk/domain` and `risk/category` to see, for example, every loss
    event of a risk domain.

    ## How it connects

    - A threat event `triggers` a loss event or a process or service; threat and loss events may sit on different
      layers (a technology event triggers an application or business event)
    - `causedBy` the threat agent (an actor, component or node)
    - `affects` the assets it harms
    - A `MotivationDriver` (the threat) `triggers` it; a vulnerability `MotivationAssessment` `influences` it
  MD

  icon "bell-notification"
  layer "application"

  annotation "event/type",
             description: "What kind of event this is (specialization of the event, see the risk and security overlay)",
             enum: %w[threat-event attack loss-event incident opportunity-event audit scan change other],
             filter: :word,
             summary: true

  annotation "event/severity",
             description: "Severity of the event",
             enum: %w[info low medium high critical],
             filter: :word,
             summary: true

  annotation "event/occurred",
             description: "When the event happened or is expected (ISO 8601 date or time)",
             title: "Occurred",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  relation :triggers, :applicationServices, :ApplicationService
  relation :triggers, :applicationEvents, :ApplicationEvent
  relation :triggers, :businessEvents, :BusinessEvent
  relation :causedBy, :businessActors, :BusinessActor
  relation :causedBy, :applicationComponents, :ApplicationComponent
  relation :causedBy, :technologyNodes, :TechnologyNode
  relation :affects, :applicationServices, :ApplicationService
  relation :affects, :applicationComponents, :ApplicationComponent
  relation :affects, :dataObjects, :DataObject
end
