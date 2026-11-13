# frozen_string_literal: true

# Grouping gathers resources of any kind that belong together by some criterion
class Archsight::Resources::Grouping < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Gathers resources of any kind, other groupings included, that belong together by some criterion.

    ## ArchiMate Definition

    **Layer:** Other (ArchiMate: composite element)
    **Aspect:** Composite

    The grouping element aggregates or composes concepts that belong together based on some common
    characteristic. Unlike a location, the criterion is not a place: a domain, a programme, a product family,
    a migration scope, the subject of a review.

    ## Usage

    Use Grouping to represent:

    - Domains and sub-domains (Payments, Identity)
    - The scope of a programme, a review or an audit
    - A product family that spans business, application and technology resources

    ## Members

    A grouping lists its members in `spec`, one key per kind, under one of two verbs:

    - `aggregates`: the member belongs to the group but also stands on its own; it can be in several groups
    - `composedOf`: the member is a part of this whole and of no other

    ```yaml
    spec:
      aggregates:
        applicationComponents: [Payment Gateway]
        businessProcesses: [Refund Handling]
        groupings: [Card Payments]
      composedOf:
        dataObjects: [Payment]
    ```

    A grouping can contain groupings, so groups nest; a grouping that contains itself (directly or through
    others) is reported by `archsight lint`. Members do not name their groups: a member's page lists the groups
    it is in.

    ## Not this kind

    - A place is a `Location`
    - The menu of the wiki is a `PageMenu`
    - Resources that only share an attribute (a team, a tag, a risk domain) need no grouping: a query or a view
      finds them
  MD

  icon "square-dashed"
  layer "other"

  # The verbs a grouping holds its members with
  MEMBER_VERBS = %i[aggregates composedOf].freeze

  # The relations shown in the template of the kind; the declared ones cover every kind
  TEMPLATE_KINDS = %w[ApplicationComponent BusinessProcess Grouping].freeze

  class << self
    # Declares MEMBER_VERBS towards every kind, this one included. Called once all kinds are loaded (see
    # lib/archsight/resources.rb), since a class body only sees the kinds loaded before it.
    def declare_members!
      @declared_relations = []
      @relations = nil
      MEMBER_VERBS.each do |verb|
        Archsight::Resources.each { |kind| relation verb, Archsight::Resources.relation_key(kind).to_sym, kind }
      end
    end

    def template_relations
      declared_relations.select { |_, _, kind| TEMPLATE_KINDS.include?(kind) }
    end
  end
end
