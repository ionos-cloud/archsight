# Architecture Modeling Guide

This guide explains how to model your architecture using ArchiMate concepts and this tool's resource types.

## Modeling Approach

Architecture modeling follows a layered approach, from business motivation down to technical implementation:

```
Motivation Layer    Why we do things (goals, stakeholders, requirements)
       |
Strategy Layer      What capabilities we need
       |
Business Layer      How business operates (processes, actors, products)
       |
Application Layer   What software supports the business
       |
Technology Layer    How software is built and deployed
```

## Starting Points

### Top-Down Modeling

Start from business motivation and work down:

1. **Define Stakeholders** - Who has interest in the architecture?
2. **Capture Goals** - What do stakeholders want to achieve?
3. **Derive Requirements** - What must the system do?
4. **Design Capabilities** - What abilities are needed?
5. **Implement Services** - What applications realize capabilities?
6. **Deploy Artifacts** - What code and infrastructure supports services?

### Bottom-Up Modeling

Start from existing infrastructure and work up:

1. **Inventory Artifacts** - What repositories and code exist?
2. **Identify Components** - What logical components are deployed?
3. **Map Services** - What application services do components provide?
4. **Trace to Business** - What business needs do services fulfill?
5. **Link to Requirements** - What compliance/business requirements are met?

## Layer-by-Layer Guidance

### Motivation Layer

Model **why** the architecture exists.

| Resource | When to Use |
|----------|-------------|
| MotivationStakeholder | For roles that have interest in architecture outcomes (CTO, Security Team, Customers) |
| MotivationGoal | For high-level objectives ("Achieve SOC 2 compliance", "Reduce latency") |
| MotivationOutcome | For measurable results ("99.9% availability", "Sub-100ms response") |

**Example chain:** Stakeholder "Security Team" → hasConcern → Goal "Achieve Compliance" → realizes → Requirement "Encrypt data at rest"

### Business Layer

Model **who** does **what** in business terms.

| Resource | When to Use |
|----------|-------------|
| BusinessActor | For teams, departments, or organizations |
| BusinessProcess | For workflows that produce business value |
| BusinessProduct | For offerings to customers (cloud services, APIs) |
| BusinessRequirement | For must-have capabilities (compliance, functional needs) |
| BusinessConstraint | For limitations (budget, regulations, technical debt) |

**Example chain:** Actor "Platform Team" → performedBy → Process "Incident Response" → servedBy → Service "Monitoring"

### Strategy Layer

Model strategic **capabilities**.

| Resource | When to Use |
|----------|-------------|
| StrategyCapability | For abilities the organization needs ("Container Orchestration", "Data Analytics") |

**Example chain:** Capability "Managed Kubernetes" → realizes → Requirement "Container Platform" and servedBy → Service "ManagedKubernetes"

### Application Layer

Model **software** that supports the business.

| Resource | When to Use |
|----------|-------------|
| ApplicationService | For high-level services (ManagedKubernetes, ObjectStorage) |
| ApplicationComponent | For deployable parts of services (API server, worker, scheduler) |
| ApplicationInterface | For APIs and integration points |
| DataObject | For data structures and schemas |

**Example chain:** Service "ManagedKubernetes" → realizedThrough → Component "kube-apiserver" → exposes → Interface "Kubernetes:RestAPI"

### Technology Layer

Model **infrastructure** and **code**.

| Resource | When to Use |
|----------|-------------|
| TechnologyArtifact | For source code repositories |
| TechnologyService | For infrastructure services (Postgres, Redis, Kubernetes platform) |
| TechnologySystemSoftware | For logical infrastructure (database cluster, message queue) |
| TechnologyArtifact | For deployed containers/binaries |
| TechnologyNode | For infrastructure instances |
| TechnologyInterface | For technical protocols and endpoints |

**Example chain:** Component "kube-apiserver" → realizedThrough → Artifact "kubernetes/kubernetes" → maintainedBy → Actor "Platform Team"

## Relation Patterns

### Realization Chain

Shows how abstract concepts become concrete:

```
BusinessRequirement
       ↓ realizes
ApplicationService
       ↓ realizedThrough
ApplicationComponent
       ↓ realizedThrough
TechnologyArtifact
```

### Service Chain

Shows how services depend on each other:

```
ApplicationService
       ↓ servedBy
TechnologyService
       ↓ suppliedBy
TechnologySystemSoftware
```

### Compliance Chain

Shows how requirements are satisfied:

```
BusinessRequirement
       ↑ satisfies
ComplianceEvidence
       ↑ evidencedBy
ApplicationService
```

## Annotation Best Practices

Use annotations to capture metadata:

- `activity/status` - Track active vs abandoned resources
- `repository/artifacts` - Container, chart, binary, etc.
- `architecture/plane` - Control plane vs data plane
- `requirement/reference` - Link to compliance standards (C5, GDPR, etc.)

## Common Patterns

### Microservice

```yaml
kind: ApplicationService
name: UserManagement
relations:
  realizedThrough:
    applicationComponents:
      - user-api
      - user-worker
```

### API Gateway Pattern

```yaml
kind: ApplicationComponent
name: api-gateway
relations:
  exposes:
    applicationInterfaces:
      - Public:RestAPI
  dependsOn:
    applicationInterfaces:
      - UserService:RestAPI
      - OrderService:RestAPI
```

### Compliance Mapping

```yaml
kind: BusinessRequirement
name: DataEncryption
annotations:
  requirement/reference: c5-2020, gdpr-2018
  requirement/type: compliance
relations:
  realizes:
    outcomes:
      - DataProtection
```
