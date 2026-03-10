# ArchiMate 3.2 Reference

## Overview

ArchiMate is an open and independent enterprise architecture modeling language developed by The Open Group. It provides a uniform representation for diagrams that describe enterprise architectures across multiple layers.

![ArchiMate](/img/archimate.png)

## Relationship Types

### Structural Relationships

| Relationship | Description |
|--------------|-------------|
| **Composition** | Represents that an element consists of one or more other concepts. Strong ownership. |
| **Aggregation** | Represents that an element combines one or more other concepts. Weaker ownership. |
| **Assignment** | Represents the allocation of responsibility, performance of behavior, storage, or execution. |
| **Realization** | Represents that an element plays a critical role in the creation, achievement, sustenance, or operation of a more abstract element. |

### Dependency Relationships

| Relationship | Description |
|--------------|-------------|
| **Serving** | Represents that an element provides its functionality to another element. |
| **Access** | Represents the ability of behavior and active structure elements to observe or act upon passive structure elements. |
| **Influence** | Represents that an element affects the implementation or achievement of some motivation element. Can be marked with +/- |
| **Association** | Represents an unspecified relationship, or one that is not represented by another ArchiMate relationship. |

### Dynamic Relationships

| Relationship | Description |
|--------------|-------------|
| **Triggering** | Represents a temporal or causal relationship between elements. |
| **Flow** | Represents transfer from one element to another. |

### Other Relationships

| Relationship | Description |
|--------------|-------------|
| **Specialization** | Represents that an element is a particular kind of another element. |

### Relationship Connectors

| Connector | Description |
|-----------|-------------|
| **Junction (And)** | Used to connect relationships of the same type with AND logic. |
| **Junction (Or)** | Used to connect relationships of the same type with OR logic. |

## Motivation Elements

| Element | Definition |
|---------|------------|
| **Stakeholder** | The role of an individual, team, or organization (or classes thereof) that represents their interests in the effects of the architecture. |
| **Driver** | An external or internal condition that motivates an organization to define its goals and implement the changes necessary to achieve them. |
| **Assessment** | The result of an analysis of the state of affairs of the enterprise with respect to some driver. |
| **Goal** | A high-level statement of intent, direction, or desired end state for an organization and its stakeholders. |
| **Outcome** | An end result, effect, or consequence of a certain state of affairs. |
| **Principle** | A statement of intent defining a general property that applies to any system in a certain context in the architecture. |
| **Requirement** | A statement of need defining a property that applies to a specific system as described by the architecture. |
| **Constraint** | A limitation on aspects of the architecture, its implementation process, or its realization. |
| **Meaning** | The knowledge or expertise present in, or the interpretation given to, a concept in a particular context. |
| **Value** | The relative worth, utility, or importance of a concept. |

## Strategy Layer Elements

| Element | Definition |
|---------|------------|
| **Resource** | An asset owned or controlled by an individual or organization. |
| **Capability** | An ability that an active structure element, such as an organization, person, or system, possesses. |
| **Value Stream** | A sequence of activities that create an overall result for a customer, stakeholder, or end user. |
| **Course of Action** | An approach or plan for configuring some capabilities and resources of the enterprise, undertaken to achieve a goal. |

## Business Layer Elements

### Active Structure Elements

| Element | Definition |
|---------|------------|
| **Business Actor** | A business entity that is capable of performing behavior. |
| **Business Role** | The responsibility for performing specific behavior, to which an actor can be assigned, or the part an actor plays in a particular action or event. |
| **Business Collaboration** | An aggregate of two or more business internal active structure elements that work together to perform collective behavior. |
| **Business Interface** | A point of access where a business service is made available to the environment. |

### Behavior Elements

| Element | Definition |
|---------|------------|
| **Business Process** | A sequence of business behaviors that achieves a specific result such as a defined set of products or business services. |
| **Business Function** | A collection of business behavior based on a chosen set of criteria (typically required business resources and/or competencies), closely aligned to an organization. |
| **Business Interaction** | A unit of collective business behavior performed by (a collaboration of) two or more business actors, business roles, or business collaborations. |
| **Business Event** | A business-related state change. |
| **Business Service** | Explicitly defined behavior that a business role, business actor, or business collaboration exposes to its environment. |

### Passive Structure Elements

| Element | Definition |
|---------|------------|
| **Business Object** | A concept used within a particular business domain. |
| **Contract** | A formal or informal specification of an agreement between a provider and a consumer that specifies rights and obligations. |
| **Representation** | A perceptible form of the information carried by a business object. |
| **Product** | A coherent collection of services and/or passive structure elements, accompanied by a contract, offered to customers. |

## Application Layer Elements

### Active Structure Elements

| Element | Definition |
|---------|------------|
| **Application Component** | An encapsulation of application functionality aligned to implementation structure, which is modular and replaceable. |
| **Application Collaboration** | An aggregate of two or more application internal active structure elements that work together to perform collective behavior. |
| **Application Interface** | A point of access where application services are made available to a user, another application component, or a node. |

### Behavior Elements

| Element | Definition |
|---------|------------|
| **Application Function** | Automated behavior that can be performed by an application component. |
| **Application Interaction** | A unit of collective application behavior performed by (a collaboration of) two or more application components. |
| **Application Process** | A sequence of application behaviors that achieves a specific result. |
| **Application Event** | An application state change. |
| **Application Service** | An explicitly defined exposed application behavior. |

### Passive Structure Elements

| Element | Definition |
|---------|------------|
| **Data Object** | Data structured for automated processing. |

## Technology Layer Elements

### Active Structure Elements

| Element | Definition |
|---------|------------|
| **Node** | A computational or physical resource that hosts, manipulates, or interacts with other computational or physical resources. |
| **Device** | A physical IT resource upon which system software and artifacts may be stored or deployed for execution. |
| **System Software** | Software that provides or contributes to an environment for storing, executing, and using software or data deployed within it. |
| **Technology Collaboration** | An aggregate of two or more technology internal active structure elements that work together to perform collective behavior. |
| **Technology Interface** | A point of access where technology services offered by a technology internal active structure element can be accessed. |
| **Path** | A link between two or more technology internal active structure elements, through which these elements can exchange data, energy, or material. |
| **Communication Network** | A set of structures and behaviors that connects devices or system software for transmission, routing, and reception of data. |

### Behavior Elements

| Element | Definition |
|---------|------------|
| **Technology Function** | A collection of technology behavior that can be performed by a technology internal active structure element. |
| **Technology Process** | A sequence of technology behaviors that achieves a specific result. |
| **Technology Interaction** | A unit of collective technology behavior performed by (a collaboration of) two or more technology internal active structure elements. |
| **Technology Event** | A technology state change. |
| **Technology Service** | An explicitly defined exposed technology behavior. |

### Passive Structure Elements

| Element | Definition |
|---------|------------|
| **Artifact** | A piece of data that is used or produced in a software development process, or by deployment and operation of an IT system. |

## Physical Elements

| Element | Definition |
|---------|------------|
| **Equipment** | One or more physical machines, tools, or instruments that can create, use, store, move, or transform materials. |
| **Facility** | A physical structure or environment. |
| **Distribution Network** | A physical network used to transport materials or energy. |
| **Material** | Tangible physical matter or energy. |

## Implementation and Migration Layer Elements

| Element | Definition |
|---------|------------|
| **Work Package** | A series of actions identified and designed to achieve specific results within specified time and resource constraints. |
| **Deliverable** | A precisely defined result of a work package. |
| **Implementation Event** | A state change related to implementation or migration. |
| **Plateau** | A relatively stable state of the architecture that exists during a limited period of time. |
| **Gap** | A statement of difference between two plateaus. |

## Composite Elements

| Element | Definition |
|---------|------------|
| **Grouping** | Aggregates or composes concepts that belong together based on some common characteristic. |
| **Location** | A conceptual or physical place or position where concepts are located (structure elements) or performed (behavior elements). |

## ArchiMate Layers

ArchiMate organizes elements into distinct layers:

1. **Motivation Layer** - Why: stakeholders, drivers, goals, requirements
2. **Strategy Layer** - What: capabilities, resources, value streams, courses of action
3. **Business Layer** - What: business processes, actors, services, objects
4. **Application Layer** - How: application components, services, data objects
5. **Technology Layer** - How: infrastructure, nodes, devices, networks
6. **Physical Layer** - Where: facilities, equipment, materials, distribution networks
7. **Implementation & Migration Layer** - When: work packages, plateaus, gaps

## Key Concepts

### Active vs Passive Structure

- **Active Structure**: Elements that can perform behavior (actors, roles, components, nodes)
- **Passive Structure**: Elements that are acted upon (objects, artifacts, data)

### Internal vs External Behavior

- **Internal Behavior**: Functions, processes, interactions
- **External Behavior**: Services (exposed functionality)

### Events

State changes that trigger or are triggered by behavior (business events, application events, technology events)

## References

- ArchiMate® 3.2 Specification Copyright © 2022 The Open Group
