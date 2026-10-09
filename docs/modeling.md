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
| MotivationRequirement | For must-have capabilities (compliance, functional needs) |
| MotivationConstraint | For limitations (budget, regulations, technical debt) |
| MotivationDriver | For threats, opportunities, regulation and market forces that motivate action (`driver/type`) |
| MotivationAssessment | For risks, vulnerabilities, findings and supplier or protection-need analyses (`assessment/type`) |
| MotivationPrinciple | For policies, guidelines and architecture principles (`principle/type`) |

**Example chain:** Stakeholder "Security Team" → hasConcern → Goal "Achieve Compliance" → realizes → Requirement "Encrypt data at rest"

### Business Layer

Model **who** does **what** in business terms.

| Resource | When to Use |
|----------|-------------|
| BusinessActor | For teams, departments, or organizations |
| BusinessProcess | For workflows that produce business value |
| BusinessProduct | For offerings to customers (cloud services, APIs) |
| BusinessControl | For controls that guide a process (access review, change approval), with an owner and executors |
| BusinessEvent | For things that happen in the business: threat events, loss events, incidents, triggers (`event/type`) |

**Example chain:** Actor "Platform Team" → performedBy → Process "Incident Response" → servedBy → Service "Monitoring"

**Controls:** Process "Incident Response" → guidedBy → Control "Escalation Review" → ownedBy / executedBy → Actor "Platform Team". How controls, requirements and evidence fit together is described under Relation Patterns below.

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
MotivationRequirement
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

### Requirements, Controls and Evidence

A requirement is the point where the process side and the application side of compliance meet:

```
Process side                                Application side

BusinessProcess                             ApplicationService / ApplicationComponent
       ↓ guidedBy                                  ↓ realizes / plans
BusinessControl                                    ↓ evidencedBy
       ↓ satisfies                          ComplianceEvidence
       ↓                                           ↓ satisfies
       └────────────→ MotivationRequirement ←────────┘
```

| Kind | Answers | Key relations |
|------|---------|---------------|
| MotivationRequirement | What must hold? | satisfied by controls and evidence; realized or planned by applications |
| BusinessControl | What do we do about it, who does it, how often? | a process is `guidedBy` it; `ownedBy` and `executedBy` actors; `satisfies` requirements; `evidencedBy` evidence |
| ComplianceEvidence | How is it met, how can it be shown? | `satisfies` requirements; `evidencedBy` from an application, a technology element or a control |

How to model it:

- **Process side.** Model a control once, let every process it governs point to it with `guidedBy`, and link it with `satisfies` to each requirement it addresses. Give it an owner (the accountable actor) and executors (the actors carrying it out). The `control/status` and `control/frequency` filters find, for example, the controls that are only partially implemented.
- **Application side.** Whether an application implements a requirement is stated on the application (`realizes`, `plans`, `evidencedBy`), never on the control. Evidence is per resource and requirement: it says how *this* service or component meets *that* requirement.
- **Evidence of a control.** A control can be `evidencedBy` evidence too. Use it for the records the control itself produces (reviews, diagrams, change history, audit logs) and set `evidence/type` to `process`, `documentation` or `audit-log`. Evidence that an application meets a requirement is linked from the application, not from a control.
- **Reading it back.** A requirement's page lists its controls and evidence as incoming `satisfies` relations. The "Requirements" table of an application page and the `requirements` blocks list what applications implement (`realizes`, `partiallyRealizes`, `plans`); controls are not part of that table.

```yaml
# process side
kind: BusinessProcess
metadata: { name: Process:ChangeManagement }
spec:
  guidedBy:
    businessControls: [Control:ChangeApproval]
---
kind: BusinessControl
metadata: { name: Control:ChangeApproval }
spec:
  ownedBy:    { businessActors: [Team:Management] }
  executedBy: { businessActors: [Team:Operations] }
  satisfies:  { motivationRequirements: [Requirement:ChangeTraceability] }
---
# application side
kind: ApplicationService
metadata: { name: Deployment }
spec:
  realizes:    { motivationRequirements: [Requirement:ChangeTraceability] }
  evidencedBy: { complianceEvidences: [Evidence:DeploymentAuditLog] }
```

### Security and Risk

Security and risk are modelled with the elements above, following the risk and security overlay of the Open Group
white paper [Modeling Enterprise Risk Management and Security with the ArchiMate Language](#reference). There is no
separate security layer: a concept is an ordinary element that carries a **type** (a specialization, the paper's
"stereotype") plus profile annotations. The type is a filterable annotation, so views, queries and lists can group by it.

| Security concept | Kind | Type annotation | Notes |
|------------------|------|-----------------|-------|
| Threat (circumstance) | `MotivationDriver` | `driver/type: threat` | also opportunity, regulation, market |
| Threat agent | `BusinessActor`, `ApplicationComponent`, `TechnologyNode` | none | the `causedBy` of an event |
| Threat event | `BusinessEvent`, `ApplicationEvent`, `TechnologyEvent` | `event/type: threat-event` or `attack` | `attack` = intentional |
| Loss event, incident | the three event kinds | `event/type: loss-event` or `incident` | the layer says where it happens |
| Risk | `MotivationAssessment` | `assessment/type: risk` | initial and residual profile, `risk/treatment` |
| Vulnerability | `MotivationAssessment` | `assessment/type: vulnerability` | `assesses` the assets it is found on |
| Control objective | `MotivationGoal` | `goal/type: control-objective` | `mitigates` the risk |
| Control measure | `MotivationRequirement` | `requirement/type: control-measure` | `realizes` the objective, `mitigates` the risk |
| Control implementation | `BusinessControl`, applications, nodes, processes | none | `satisfies` / `realizes` the measure |
| Proof of the control | `ComplianceEvidence` | `evidence/type` | `evidence/status: not-applicable` where the requirement does not apply |
| Asset at risk | any application, technology, data or process kind | `asset/value`, `asset/confidentiality`, `asset/integrity`, `asset/availability` | the protection need (BSI Schutzbedarf) |
| Policy (design level) | `MotivationPrinciple` | `principle/type: security-policy` or `risk-policy` | status, validity, framework mapping |
| Operational policy, regulation | `MotivationConstraint` | none | the paper has no element for operational policy |
| Risk domain | none; annotation `risk/domain` | `risk/domain`, `risk/category` | group by it with a query or a `View` |

The chain, as in the paper's Coldhard Steel example:

```
MotivationDriver (threat) ──influences──→ MotivationAssessment (risk) ←──mitigates── MotivationGoal (control objective)
        │ triggers                                  ↑ assesses                              ↑ realizes
        ↓                                           │                              MotivationRequirement (control measure)
BusinessEvent (loss event) ←──influences── MotivationAssessment (vulnerability)             ↑ satisfies
        ↑ triggers                                                                 BusinessControl / asset ──evidencedBy──→ ComplianceEvidence
TechnologyEvent / ApplicationEvent (threat event, attack)
```

```yaml
kind: MotivationDriver
metadata: { name: Threat:Intrusion, annotations: { driver/type: threat } }
spec:
  influences: { motivationAssessments: [Risk:Intrusion] }
  triggers:   { businessEvents: [Loss:DataLeak] }
---
kind: MotivationAssessment
metadata:
  name: Risk:Intrusion
  annotations:
    assessment/type: risk
    risk/initial-likelihood: high
    risk/residual-likelihood: low
    risk/treatment: mitigate
    risk/domain: customer-data
spec:
  ownedBy: { businessActors: [Team:Security] }
  assesses: { technologyNodes: [Node:Web1] }
---
kind: MotivationGoal
metadata: { name: Objective:ReduceExposure, annotations: { goal/type: control-objective } }
spec:
  mitigates: { motivationAssessments: [Risk:Intrusion] }
---
kind: MotivationRequirement
metadata: { name: Measure:Firewall, annotations: { requirement/type: control-measure } }
spec:
  realizes: { goals: [Objective:ReduceExposure] }
  mitigates: { motivationAssessments: [Risk:Intrusion] }
---
kind: BusinessControl
metadata: { name: Control:FirewallReview }
spec:
  satisfies: { motivationRequirements: [Measure:Firewall] }
  mitigates: { motivationAssessments: [Risk:Intrusion] }
```

How to model it:

- **Events and their types.** A threat event `triggers` a loss event; the three event kinds (business, application,
  technology) say on which level it happens and a technology event may trigger an application or business event. Use
  `event/type` to tell threat events, attacks, loss events, incidents, opportunity events, audits, scans and changes apart.
- **Vulnerability scan.** One `MotivationAssessment` of type `vulnerability` per finding, `assesses` every node it was
  found on, `influences` the loss events and risks it makes possible. Business impact follows from the model: the node
  serves services, services serve processes.
- **Grouping (risk domains).** ArchiMate has no domain element; set `risk/domain` (and `risk/category`: hazard,
  financial, operational, strategic, compliance, security) on events, assessments, drivers, requirements, controls and
  assets, and query or build a `View` per domain to see its threats, risks, measures and assets together.
- **Policies.** The text of a policy is a `Page`; the structured statement (owner, validity, status, framework) is a
  `MotivationPrinciple` that links to the page with `[[Page]]`.
- **Initial and residual risk.** Record both on the assessment (`risk/initial-*`, `risk/residual-*`) and the decision
  in `risk/treatment`.

<a id="reference"></a>
**Reference:** Band, Engelsman, Feltus, González Paredes, Hietala, Jonkers, Massart,
[Modeling Enterprise Risk Management and Security with the ArchiMate Language](https://pure.unamur.be/ws/files/12366722/Modeling_Enterprise_Risk_Management_and_Secutity_with_the_ArchiMate_Language.pdf),
The Open Group white paper (ArchiMate 2.1). For the NIST OSCAL vocabulary used for names of assessment and evidence
fields see [OSCAL](https://pages.nist.gov/OSCAL/learn/concepts/layer/).

### Compliance Chain

Shows how requirements are satisfied:

```
MotivationRequirement
       ↑ satisfies
ComplianceEvidence
       ↑ evidencedBy
ApplicationService (or TechnologyService / TechnologySystemSoftware)
```

Technology elements such as a Kubernetes cluster runtime can plan, realize and be evidenced
for requirements directly, so the requirement does not have to be attached to a placeholder
ApplicationService. Applications deployed on them point to the TechnologyService with `servedBy`.

ApplicationComponents can be evidenced as well (`realizes` / `plans motivationRequirements`, `evidencedBy
complianceEvidences`), so requirements can be answered per component and not only per service.

A ComplianceEvidence answers "how is the requirement met" in structured markdown fields next to
`architecture/description` (kept as a short summary): `evidence/mechanism`, `evidence/coverage`,
`evidence/operatorView` (does it hold against operators or only against other tenants),
`evidence/verification`, `evidence/gaps` and `evidence/sources`. Because they are separate annotations they can be
queried, for example `ComplianceEvidence: evidence/gaps =~ "needs review"`.

### Derived References

Text and diagrams already say which resources they are about, so archsight turns that into relations instead of asking you
to repeat it in YAML. There are two, and they are never written in a file:

| Relation | Comes from | Where |
|----------|------------|-------|
| `mentions` | `[[Target]]`, `[[Kind/Name]]` links and `![[View/Name]]` embeds | the content of a page, the description of any resource, any markdown annotation |
| `depicts` | the `resource "..."` of the nodes of a diagram | ```` ```asd ```` blocks and `![](file.asd)` files in those texts, and the `architecture/diagram` of any resource |

```
Page "Architecture overview"  --mentions-->  ApplicationComponent "Core:Database"     ([[Core:Database]])
Page "Architecture overview"  --depicts--->  ApplicationComponent "Web:API"           (resource "Web:API" in a diagram)
```

They are rebuilt on every load, so they cannot drift from the text. They show on both sides: a resource lists the pages
that mention and depict it under Relations ("Page / mentions"), and a page lists what it refers to. Only an exact name counts: a
page by its name or title, `Kind/Name`, or a resource name that exists once. Part of a name, a name that exists in several
kinds, and an unknown name do not make a relation (`archsight lint` reports unknown links in pages). Links in code are shown as
written and do not count, and neither does a resource referring to itself. Views and requirements blocks pick resources with a
query when they run, so they name nothing.

Derived relations are followed like written ones: queries (`ApplicationComponent: <- Page`, `Page: -> ApplicationComponent`),
transitive queries and impact analysis. A page that mentions a component therefore shows up when you ask what a change to the
component affects, which tells you which pages to update, and a resource that only a page mentions is not an orphan
(`<- none`). To leave them out of a query, exclude the verbs: `ApplicationComponent: ~{!mentions,depicts}> TechnologyArtifact`.
Computed annotations (costs, teams, repositories) follow written relations only, so a link in a text never changes a number.
They are not part of the editor's relation form, and `mentions:` or `depicts:` in a file is an unknown verb.

## Annotation Best Practices

Use annotations to capture metadata:

- `activity/status` - Track active vs abandoned resources
- `repository/artifacts` - Container, chart, binary, etc.
- `architecture/plane` - Control plane vs data plane
- `requirement/reference` - Link to compliance standards (C5, GDPR, etc.)
- `architecture/diagram` - A hand-drawn [`.asd` diagram](diagram.md#the-architecturediagram-annotation), shown next to the generated dependency graph
  (`.asd` code blocks also render inside `architecture/description` markdown). Nodes can link to resources with `resource "Name"`.

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
kind: MotivationRequirement
name: DataEncryption
annotations:
  requirement/reference: c5-2020, gdpr-2018
  requirement/type: compliance
relations:
  realizes:
    outcomes:
      - DataProtection
```

## Renamed Kinds

Requirements and constraints are Motivation elements in ArchiMate, so their kinds are named that way:

| Old | New |
|-----|-----|
| `BusinessRequirement` | `MotivationRequirement` |
| `BusinessConstraint` | `MotivationConstraint` |
| relation key `businessRequirements` | `motivationRequirements` |
| relation key `businessConstraints` | `motivationConstraints` |

Both kinds moved from the Business to the Motivation layer. Their annotations (`requirement/*`) are unchanged.

For now the old names keep working: files with `kind: BusinessRequirement` or `businessRequirements:` keys load as they are, queries such as `BusinessRequirement: requirement/priority == "must"` and `~> BusinessRequirement` still match, and old links to `/kinds/BusinessRequirement/...` still open. Everything shown (the UI, the API, files written by the inline editor) uses the new names.

`archsight lint` lists every use of an old name as a deprecation, with the file and line, without failing. Replace them, for example with a find and replace over your resources directory (YAML files and the queries in markdown pages):

```bash
find resources \( -name '*.yaml' -o -name '*.md' \) -exec sed -i.bak \
  -e 's/BusinessRequirement/MotivationRequirement/g' -e 's/BusinessConstraint/MotivationConstraint/g' \
  -e 's/businessRequirements/motivationRequirements/g' -e 's/businessConstraints/motivationConstraints/g' {} +
```

The old names will be removed in a future release.
