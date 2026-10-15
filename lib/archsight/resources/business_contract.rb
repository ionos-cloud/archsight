# frozen_string_literal: true

# BusinessContract represents an agreement between a provider and a consumer
class Archsight::Resources::BusinessContract < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents an agreement between a provider and a consumer: the rights and obligations both agreed to.

    ## ArchiMate Definition

    **Layer:** Business
    **Aspect:** Passive Structure

    A contract is a formal or informal specification of an agreement between a provider and a consumer that
    specifies rights and obligations. It is a specialization of a business object. A product is accompanied by a
    contract, and a contract can consist of parts.

    ## Usage

    Use BusinessContract to represent:

    - Framework contracts with a customer
    - Call-offs under a framework contract (an order for one more block of capacity)
    - Service level agreements
    - Amendments of a contract

    A contract is a `BusinessContract`, not a `DataObject` and not text in a description: only then do the graph,
    views and analyses see what it agrees, who agreed it and what delivered it.

    ## How it connects

    - A `BusinessProduct` `aggregates` the contract that comes with it
    - It is `agreedBy` its parties: the actual organisations (the customer, the provider), not a generic role
    - It is `composedOf` its parts: call-offs, SLAs and amendments, which are contracts themselves (no cycles)
    - It `covers` what it obliges the provider to deliver: equipment, nodes, technology and application services
    - It is `realizedThrough` the `ImplementationDeliverable` that fulfils it; the `ImplementationWorkPackage` that
      `realizes` the deliverable `affects` the equipment it installs

    The other side shows these as incoming relations: the contracts an actor agreed, what covers a piece of
    equipment or a service, the contract a deliverable fulfils.
  MD

  icon "journal-page"
  layer "business"

  annotation "contract/type",
             description: "What kind of contract this is",
             enum: %w[framework call-off sla amendment other],
             filter: :word,
             summary: true
  annotation "contract/reference",
             description: "The contract number",
             title: "Reference",
             summary: true
  annotation "contract/from",
             description: "When the contract starts (ISO 8601 date or time)",
             title: "From",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }
  annotation "contract/until",
             description: "When the contract ends (ISO 8601 date or time)",
             title: "Until",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) }

  relation :agreedBy, :businessActors, :BusinessActor
  relation :composedOf, :businessContracts, :BusinessContract
  relation :covers, :technologyEquipment, :TechnologyEquipment
  relation :covers, :technologyNodes, :TechnologyNode
  relation :covers, :technologyServices, :TechnologyService
  relation :covers, :applicationServices, :ApplicationService
  relation :realizedThrough, :implementationDeliverables, :ImplementationDeliverable
end
