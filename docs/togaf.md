# TOGAF Reference

## How TOGAF Relates to Archsight

Archsight is a Ruby-based enterprise architecture documentation tool that uses a complementary combination of TOGAF and ArchiMate standards:

**TOGAF's Role - Conceptual Foundation:**
TOGAF provides the **enterprise architecture framework and metamodel** - defining what architecture elements exist, how they relate, and why they matter. It establishes:

- The content metamodel (entity types and their relationships)
- Architecture domains (Business, Data, Application, Technology)
- Governance and lifecycle concepts (baseline, target, transition architectures)
- Strategic alignment principles (drivers → goals → objectives → capabilities)

**ArchiMate's Role - Visual Communication:**
ArchiMate provides the **modeling language and notation** - defining how to visually represent and communicate architecture. Archsight uses ArchiMate concepts for:

- Visual notation and diagram syntax
- GraphViz-based visualizations
- Standardized representation of resource relationships
- Communication with stakeholders

**Archsight's Implementation:**

- **YAML Resources** implement TOGAF's content metamodel entities (Business Actor, Application Component, Technology Service, etc.)
- **Resource Relations** capture TOGAF's entity relationships for traceability and impact analysis
- **Directory Structure** follows TOGAF's four architecture domains
- **Visualizations** use ArchiMate-inspired notation to communicate these TOGAF-based resources

**In Summary:** TOGAF defines *what to document and why*, ArchiMate defines *how to visualize it*, and Archsight provides the *tool to manage and render* both as YAML-based architecture documentation.

This reference helps Archsight users understand the TOGAF concepts underlying their architecture resources, while recognizing that visual communication follows ArchiMate conventions.

## Overview

TOGAF (The Open Group Architecture Framework) is a comprehensive framework for enterprise architecture that provides an approach for designing, planning, implementing, and governing enterprise information technology architecture. TOGAF is developed and maintained by The Open Group.

![TOGAF](/img/togaf-high-level.png)

## Architecture Development Method (ADM)

The ADM is TOGAF's core - a step-by-step iterative approach to developing enterprise architecture:

1. **Preliminary Phase** - Preparation and initiation
2. **Phase A: Architecture Vision** - Define scope, stakeholders, create vision
3. **Phase B: Business Architecture** - Business strategy, processes, capabilities
4. **Phase C: Information Systems** - Application and Data Architectures
5. **Phase D: Technology Architecture** - Infrastructure and platforms
6. **Phase E: Opportunities & Solutions** - Initial implementation planning
7. **Phase F: Migration Planning** - Detailed migration plans
8. **Phase G: Implementation Governance** - Oversight of implementation
9. **Phase H: Architecture Change Management** - Manage ongoing change
10. **Requirements Management** - Central hub managing requirements

The ADM is iterative, adaptable to organizational needs, and stakeholder-driven.

## Architecture Domains

TOGAF organizes architecture into four interconnected domains:

### Business Architecture

Strategy, governance, organization, and business processes.

**Elements:** Business capabilities, value streams, processes, functions, services, organizational structure

### Data Architecture

Logical and physical data assets and management.

**Elements:** Data entities, models, quality, governance, master data

### Application Architecture

Application systems, interactions, and business process relationships.

**Elements:** Application components, services, interfaces, functions

### Technology Architecture

Software and hardware capabilities supporting business, data, and applications.

**Elements:** Platforms, infrastructure, network, hardware, middleware, technology services

## TOGAF Content Metamodel

The metamodel defines architectural entities and their relationships across all domains. Understanding these connections is essential for comprehensive architecture documentation.

### Core Entity Categories

**Motivation Layer:**

- **Driver** → **Goal** → **Objective** → **Course of Action**
- Measures track objectives; value streams deliver capabilities

**Organizational:**

- **Organization Unit** contains **Actors** performing **Roles**
- Actors and roles participate in business functions and processes

**Business Behavior:**

- **Business Capability** realized by **Business Functions** and **Processes**
- **Business Service** uses functions/processes, automates application services
- **Value Stream** enabled by capabilities, operationalized through processes
- **Events** trigger processes; **Products** result from them

**Data Architecture:**

- **Data Entity** → **Logical Data Component** → **Physical Data Component**
- Data entities accessed by business/application services

**Application Architecture:**

- **Application Service** → **Logical Application Component** → **Physical Application Component**
- Application services automate business services, use data components

**Technology Architecture:**

- **Technology Service** → **Logical Technology Component** → **Physical Technology Component**
- Technology services support application services and components

**Cross-Cutting:**

- **Principle**, **Constraint**, **Requirement**, **Gap**, **Work Package**, **Location**

### Critical Relationships

1. **Traceability**: Drivers → Goals → Objectives → Course of Action → Business Elements → Applications → Technology
2. **Service Layers**: Business Services → Application Services → Technology Services
3. **Logical-Physical**: All domains separate logical design from physical implementation
4. **Value Chain**: Value Stream → Business Capability → Business Service → Application Service
5. **Data Flow**: Business Process → Data Entity → Logical Component → Physical Component

### Artifacts & Deliverables

**Artifacts** (work products describing architecture):

- **Catalogs** - Lists of building blocks
- **Matrices** - Relationship mappings
- **Diagrams** - Visual representations

**Deliverables** (contractual work products):

- Architecture Vision, Definition Document, Requirements Specification
- Architecture Roadmap, Capability Assessment
- Implementation and Migration Plan, Transition Architecture

## Building Blocks

### Architecture Building Blocks (ABBs)

Define **what** functionality is required - architecture entities, relationships, and requirements that guide solution development.

### Solution Building Blocks (SBBs)

Define **how** functionality is implemented - specific implementations mapping to actual products and technologies.

**Characteristics:** Well-defined interfaces and functionality, interoperable, replaceable, reusable

## Architecture Governance & Change

### Change Profiles

- **Rapid Change** - Fast iterations, minimal governance, focus on innovation
- **Functional Change** - Balanced approach, standard governance (most common)
- **Robust Change** - Rigorous governance, high assurance, compliance-critical

### Governance Framework

- Architecture Board and contracts
- Compliance reviews at project milestones
- Configuration and version management
- Dispensations and exception handling

### Key Concepts

- **Baseline Architecture** - Current state
- **Target Architecture** - Desired future state
- **Transition Architectures** - Intermediate states
- **Gap Analysis** - Compare baseline to target, identify changes needed
- **Architecture Repository** - Central storage for metamodel, capability, landscape, standards

## Integration with Other Frameworks

### TOGAF and ArchiMate

- **TOGAF** provides the process (ADM) and content framework
- **ArchiMate** provides the modeling language and notation
- Complementary: ArchiMate is TOGAF's recommended modeling language

### TOGAF and Agile

- ADM adapts to agile delivery through iterations
- Architecture vision provides guardrails
- Continuous architecture refinement supports rapid change

### Other Integrations

- **COBIT** - IT governance alignment
- **ITIL** - Service management integration

## Architecture Principles

General rules guiding IT resource use and deployment:

**Structure:** Name, Statement, Rationale, Implications

**Examples:**

- Business Continuity - Ensure operations continue
- Data is an Asset - Manage strategically
- Data is Shared - Eliminate redundancy
- Technology Independence - Avoid vendor lock-in
- Interoperability - Enable seamless integration
- Requirements Based Change - Justify all changes

## Viewpoints and Views

### Viewpoint

Specification for constructing views - defines stakeholders, concerns, models, techniques, and notations. Reusable across projects.

### View

Representation of the system from specific stakeholder perspectives, addressing their concerns using models defined by viewpoints.

**Common Viewpoints:** Enterprise, Information System, Computing Platform, Communications, Security, Business Process, Application

## Key TOGAF Benefits

- **Standardization** - Common language and framework across the enterprise
- **Efficiency** - Reusable processes and proven patterns
- **Risk Reduction** - Proven approach minimizes project failures
- **Better Decisions** - Holistic view enables informed strategic choices
- **Alignment** - Ensures business and IT work toward common goals
- **Flexibility** - Adaptable to various industries and organizational contexts

## TOGAF Terminology Quick Reference

- **Enterprise** - Collection of organizations with common goals
- **Architecture** - Fundamental concepts/properties of a system in its environment
- **Building Block** - Component of business or IT capability (reusable architectural component)
- **Artifact** - Architectural work product (catalog, matrix, diagram)
- **Deliverable** - Contractually specified work product
- **Viewpoint** - Perspective from which a view is taken
- **View** - System representation addressing specific concerns
- **Baseline** - Current architecture state
- **Target** - Desired future architecture state
- **Gap** - Difference between baseline and target requiring action

## Resources & Version History

**Reference:** The TOGAF® Standard, 10th Edition - The [Open Group Architecture Framework](https://www.opengroup.org/togaf)
Copyright © The Open Group
