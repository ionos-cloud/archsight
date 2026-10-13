# Architecture Modeling Guide

This guide explains how to model your architecture using ArchiMate concepts and this tool's resource types.

## Modeling Approach

Architecture modeling follows a layered approach, from business motivation down to technical implementation:

```
Motivation Layer              Why we do things (goals, stakeholders, requirements, risks, policies)
       |
Strategy Layer                What capabilities we need
       |
Implementation & Migration    How the change happens (work packages, plateaus, gaps)
       |
Business Layer                How business operates (processes, actors, products)
       |
Application Layer             What software supports the business
       |
Technology Layer              How software is built and deployed, and where it runs (facilities, equipment, networks)
```

The sidebar, the search facets, the metamodel diagram and these guides list the layers in this order, top to bottom;
the tool's own kinds (pages, views, imports, analyses) come last under "Other".

## Direction of Relations

Model and read the architecture **top-down**: Motivation, Strategy, Business, Application, Technology; the
Implementation & Migration layer describes change across all of them. A relation is written on an element and points
to what that element depends on, is served by, or is answered by. Following relations from a high-level element
therefore walks down to people, code and infrastructure, and the relations form a DAG: nothing may lead back to where
it started. `archsight lint` reports every cycle (only `dependsOn` is exempt, because components and services may depend on each
other at runtime). `specializes`, `composedOf` and `aggregates` are checked per verb, see "Concept and Implementation" and "Deployment".

There are two families of verbs:

| Family | Verbs | Written on | Points to |
|--------|-------|------------|-----------|
| Responsibility and provider (down) | `performedBy`, `ownedBy`, `executedBy`, `servedBy`, `guidedBy`, `maintainedBy`, `contributedBy`, `hasConcern`, `realizedThrough`, `exposes`, `mitigatedBy`, `influences`, `triggers`, `affects`, `assesses`, `contains`, `closedBy`, `compares` | the element that needs, uses or is concerned with something | what provides it or is responsible for it |
| Realization (up) | `realizes`, `partiallyRealizes`, `plans`, `satisfies`, `evidencedBy` (on the evidenced element), `provides` | the concrete element | the abstract element it answers to (requirement, goal, capability, plateau) |

Rules:

- A pair of kinds never has the same relation in both directions: a goal `realizes` a requirement, a requirement does not
  `realize` a goal. Reverse relations are shown for free as incoming relations.
- Responsibility ends at the actor: process, control, risk, policy, work package point to a `BusinessRole`, the role
  points to the `BusinessActor` that holds it, and the actor points to nothing further.
- The docs draw realization chains top-down ("Requirement, down to Service") while the data is stored on the concrete
  element, so the file of a service says what it realizes.
- `mentions` and `depicts` are not part of this structure. They are derived from the text and diagrams of a resource
  (never written in a file) and show how things are linked sideways, in prose and pictures. They neither follow nor
  contradict the direction above and are left out of the cycle check.

## Choosing the Kind

Four kinds carry most of a model: StrategyCapability, BusinessProduct, ApplicationService and ApplicationComponent.
Each answers one question. The test decides the kind, not the name.

| Kind | Question | Test | Name |
|------|----------|------|------|
| StrategyCapability | What must the organization be *able* to do? | Survives swapping product, team and technology; not a certificate or quality | ability noun phrase ("Payment Processing"), never a product, team or technology |
| BusinessProduct | What does a customer buy or contract? | Appears on a price list, catalog or customer documentation | market name ("Online Checkout") |
| ApplicationService | What behaviour does software offer a consumer? | Describable without naming repos, deployments or runtime objects; one owning actor | the function, not the technology or deployment object ("Payment Authorization") |
| ApplicationComponent | What is built, deployed and versioned? | Has artifacts and a `component/type`; can be deployed or linked | the part, by runtime role (API, Operator, Worker), not by repo category ("Payments:API") |

**Decision questions**, asked in order for any new element:

1. Is it something the organization must be able to do, whoever or whatever does it? Capability.
2. Is it something a customer selects, buys or signs a contract for? Product.
3. Is it a function another system or a user calls or consumes, nameable without saying how it is built? Service.
4. Is it something that is built, versioned and deployed or linked? Component.
5. Is it a repository, package, image or binary? Artifact.
6. Is it a proof, rule or obligation (certificate, regulation, policy)? Motivation or Compliance, not one of the above.
7. Is it another name or id of something already modeled? `architecture/aliases` or `link/*` on that element, not a
   new element.
8. Does the same name already exist as a different kind? Check whether the two are really different. If they are not,
   keep the element at the highest level where the test holds and link the others to it.

**Rules**

1. One path up: Product `realizes` Capability, Product `servedBy` Service, Service `realizedThrough` Component,
   Component `realizedThrough` Artifact. Capability `servedBy` Service only for internal capabilities that no product
   carries.
2. A component belongs to exactly one service; one service using another is `dependsOn` between the services (see
   [Service Chain](#service-chain)), not the same component listed twice.
3. An artifact is realized by exactly one component. When one repository holds several finer components (a monorepo),
   the larger logical component (`component/type: module`) is realized by the artifact and the finer components
   `dependsOn` it; the services use the finer components, and their rollups still reach the repository.
4. A service whose only component has the same name is a smell: name the service by its function, or fold it into the
   service it belongs to.
5. Test, tooling and infrastructure-as-code repositories are not components of their own. They go on the component
   they build, test or deploy.
6. A product served by nearly every service is a catalog, not a product. A service that serves many products is a
   shared service and is modeled once.
7. Certifications and regulations are Motivation (requirement or constraint) with Compliance evidence, not
   capabilities.
8. Other identifiers of an element (register ids, wiki or ticket pages) are `architecture/aliases` and `link/*` on the
   element itself, never a parallel element.

**Checked by `archsight lint`**

Rules 1 to 4 are checked on every `archsight lint` run and reported as **warnings** (section "Modeling warnings"),
never as errors, so they do not make the lint fail: they point at decisions to review and have legitimate exceptions,
such as an internal service or a capability that no product carries yet.

| Warning | Rule |
|---------|------|
| `ApplicationComponent 'Payments:API' is realized by 2 services: 'Payment Authorization', 'Refunds'` | 2 |
| `TechnologyArtifact 'Repo:payments-api' is realized by 2 components: ...` | 3 |
| `ApplicationService 'Billing' has one component with the same name` | 4 |
| `BusinessProduct 'Online Checkout' is served by no ApplicationService` | 1 |
| `ApplicationService 'Ledger' is not served to any product or process` | 1 |
| `StrategyCapability 'Payment Processing' is realized by no product` | 1 |
| `ApplicationComponent 'alice:shop' is generated from 2 repositories with the same module path: ...` | import, see [Classifying components](#classifying-components) |

A service counts as served when a product or a process is `servedBy` it, directly or through other services that
`dependsOn` it. Each finding starts with the file and line of the resource, like the errors.

**Example chain**

```
StrategyCapability "Payment Processing"
       ↑ realizes
BusinessProduct "Online Checkout"
       ↓ servedBy
ApplicationService "Payment Authorization"
       ↓ realizedThrough
ApplicationComponent "Payments:API"
       ↓ realizedThrough
TechnologyArtifact "Repo:payments-api"
```

The chain is part of `examples/archsight` (`strategy/`, `business/`, `services/`, `components/`, `technology/`).

**Anti-patterns**

| Anti-pattern | Fix |
|--------------|-----|
| A service named after a deployment object (ingress route, Helm release, admin endpoint) | Name it by the function it offers; the deployment object is part of the component or artifact |
| Components named after repo categories ("Testing", "Tools", "Infrastructure") | Name components by runtime role; put test, tooling and infrastructure repositories on the component they belong to |
| A catalog product that everything serves | Model the products customers really buy; the catalog is a view or page |
| A certificate modeled as a capability | Requirement or constraint with Compliance evidence |
| A parallel set of services that re-groups the same components for an inventory or register | `architecture/aliases` and `link/*` on the real service |

## Choosing the Kind: Infrastructure

Infrastructure is modeled in four tiers: **where** (Location, TechnologyFacility), **physical** (TechnologyEquipment), **network**
(TechnologyCommunicationNetwork) and **compute** (TechnologyNode, TechnologySystemSoftware, TechnologyService,
TechnologyArtifact). The same principle holds as above: the test decides the kind, not the name.

| Kind | Question | Test | Name |
|------|----------|------|------|
| Location | In which region or country is it? | A place on a map, not a building; holds facilities | the place ("Location:Germany:Frankfurt") |
| TechnologyFacility | In which building or site does hardware stand? | Has an address and can be visited; can be nested (campus, hall) | the site ("Facility:Frankfurt:HallA") |
| TechnologyEquipment | Which physical thing can you touch? | Racks, fabrics, fibre routes, carrier circuits; no software of its own | the thing and its place ("Equipment:Link:Frankfurt-Madrid") |
| TechnologyCommunicationNetwork | What carries data between nodes? | Has a network role (`network/type`); exists beyond any single link | role and scope ("Network:Management:Frankfurt") |
| TechnologyNode | On which machine does software run? | A server, VM or appliance with a lifecycle of its own | the host or host role ("Node:Frankfurt:Web01") |
| TechnologySystemSoftware | What software hosts other software or data? | An operating system, database cluster, routing stack, platform | the product and role ("Tech:Routing:EVPN") |
| TechnologyService | What does infrastructure offer to its consumers? | Consumed without knowing which nodes run it | the offering ("Network:Backbone", "Postgres") |
| TechnologyArtifact | Which file is built and deployed? | A repository, image, package or binary | the artifact ("Repo:payments-api") |

**Decision questions**, asked in order for any new infrastructure element:

1. Is it a country, metro or region? Location.
2. Is it a building, campus, hall or site that can be visited? TechnologyFacility.
3. Is it a physical thing (rack, switch fabric, fibre, circuit) without software of its own? TechnologyEquipment.
4. Does it carry data between nodes, with a role such as underlay, overlay, management, public or VPN?
   TechnologyCommunicationNetwork.
5. Is it a machine (physical or virtual) that software runs on? TechnologyNode.
6. Is it software that hosts other software, data or traffic? TechnologySystemSoftware.
7. Is it something consumed by others without them knowing how it is run? TechnologyService.
8. Is it a file that is built and deployed? TechnologyArtifact.

**Rules**

1. One element per thing, many `locatedAt`: a service, network or cluster that runs in three data centers is one
   element with three relations, never a copy per site.
2. A link between sites is one TechnologyEquipment (`equipment/type: link`) `locatedAt` exactly its two facilities. A backbone
   is TechnologyEquipment `composedOf` its links.
3. Physical before logical: a network is `realizedBy` the TechnologyEquipment it runs over and the system software that
   implements it; an overlay or VPN is `servedBy` the network it runs over.
4. No element per tenant or customer network: the overlay is one network, its tenants are instances of it.
5. A mesh is `network/topology: mesh` on one network, not an element per pair of sites. Single tunnels are
   sub-networks only when they have their own owner or capacity.
6. Concept and implementation with `specializes` (management network → management network of one site), structure
   with `composedOf` (metro network → site networks, campus → halls, backbone → links).
7. A network that supports a metro region is `locatedAt` the Location and `composedOf` the networks of its sites.
8. Nodes attach to networks with `servedBy` and stand in facilities with `locatedAt`.
9. An overlay that software builds (an SDN agent wiring tenant networks on each host, an operator creating VXLAN
   segments, a load-balancer controller announcing public addresses) is `realizedBy` that `ApplicationComponent` or
   `ApplicationService` (ArchiMate cross-layer realization). This holds even when the software runs on the nodes the
   network serves: point at the application component, not at the node's system software, which would close a cycle
   (network → system software → node → network).

**Checked by `archsight lint`**

As above, these are **warnings** in the "Modeling warnings" section and never fail the lint:

| Warning | Rule |
|---------|------|
| `TechnologyEquipment 'Equipment:Link:A-B' is a link located at 1 facility, not 2` | 2 |
| `TechnologyCommunicationNetwork 'Network:Overlay:EVPN' is an overlay network served by no network` | 3 |
| `TechnologyFacility 'Facility:Madrid:DC' is located at no Location` | where |
| `TechnologyEquipment 'Equipment:Rack01' is located at no TechnologyFacility` | where |

Nested facilities need no location of their own (the outermost facility has it), and TechnologyEquipment that is part of other
TechnologyEquipment, or composed of placed parts, needs no facility of its own.

**Example chain**

```
Location "Location:Germany:Frankfurt"
       ↑ locatedAt
TechnologyFacility "Facility:Frankfurt:Campus"  ──composedOf──>  TechnologyFacility "Facility:Frankfurt:HallA"
       ↑ locatedAt (both ends)                              ↑ locatedAt
TechnologyEquipment "Equipment:Link:Frankfurt-Madrid" (link)       TechnologyNode "Node:Frankfurt:Web01"
       ↑ composedOf                                         │ servedBy
TechnologyEquipment "Equipment:Backbone"                              ↓
       ↑ realizedBy                                     TechnologyCommunicationNetwork "Network:Management:Frankfurt"
TechnologyService "Network:Backbone"
```

The overlay `Network:Overlay:EVPN` is `servedBy` the underlay and `realizedBy` the routing software
`Tech:Routing:EVPN`. All of it is in `examples/archsight/technology/` (`facilities.yaml`, `networks.yaml`), walked
through on the example page "Infrastructure Modeling".

**Anti-patterns**

| Anti-pattern | Fix |
|--------------|-----|
| A data center modeled as a TechnologyNode | TechnologyFacility; the servers in it are nodes `locatedAt` it |
| Sites as annotations (`deployment/locations: dc-1,dc-2`) | TechnologyFacility elements and `locatedAt` |
| One copy of a service or cluster per site | One element `locatedAt` every site |
| A Location used for a building | TechnologyFacility `locatedAt` the Location |
| A link or fibre route as a TechnologyService | TechnologyEquipment `link`; the network service is `realizedBy` it |
| A network per tenant or customer | One overlay network; tenants stay out of the model |
| An element per pair of sites in a mesh | One network with `network/topology: mesh` |
| An overlay or VPN with nothing under it | `servedBy` the underlay or the network it tunnels through |

## Identity and Links

A resource has one **name**, the key everything refers to (relations, `[[wiki links]]`, URLs). Two annotations say more
about who it is and where else it lives. Both are available on every resource kind (pages have the links too).

### Aliases

`architecture/aliases` holds the other identifiers of a resource, comma-separated: `ApplicationService:Foo` can also be
`ITGS:A001`. Aliases are **unique among the resources of a kind** (`archsight lint` reports a duplicate with both
resources); the same alias on resources of different kinds is fine, like names. They are found, not resolved:

```
ITGS:A001                                              # the search box: the name shortcut also tests aliases
ApplicationService: architecture/aliases == "ITGS:A001"
name == "ITGS:A001"
```

An alias is an identifier, so it is shown as plain text and is not a facet in the sidebar (it would only ever point at
one resource). It is not a name: it cannot be used in a relation, a `[[wiki link]]` or a URL. When two documents describe
the same resource, their aliases (and tags) are added together instead of one replacing the other.

For kind authors: `annotation "key", unique: true` makes any annotation an identifier of this kind: unique per kind,
checked by `archsight lint`, shown as plain text.

### Links

`link/<name>` holds a URL on any resource. The name says which system: `link/confluence`, `link/jira`,
`link/servicenow`; a second link into the same system gets another name (`link/confluence-isms`). A link has **no
direction**: it is where the resource comes from, where it was published to, or just a related page. A page writes them
as `links:` in its frontmatter (see [Pages](/doc/pages)):

```yaml
kind: ApplicationService
metadata:
  name: Foo
  annotations:
    architecture/aliases: ITGS:A001
    link/confluence: https://confluence.example.com/spaces/ARCH/pages/12345/Foo
    link/jira: https://jira.example.com/browse/ARCH-12
```

Links render with the icon of their system wherever a resource or page is shown. Artifacts also carry many generated
`link/*` entries (links found in the README); they are listed apart from the ones you write.

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

### Strategy Layer

Model strategic **capabilities**.

| Resource | When to Use |
|----------|-------------|
| StrategyCapability | For abilities the organization needs ("Payment Processing", "Data Analytics"); not a product, team or certificate |

**Example chain:** Product "Online Checkout" → realizes → Capability "Payment Processing" → realizes → Requirement "Card Payments" (see [Choosing the Kind](#choosing-the-kind))

### Implementation & Migration Layer

Model **change**: what is done, what it delivers and how the architecture looks before and after.

| Resource | When to Use |
|----------|-------------|
| ImplementationWorkPackage | For projects, measures, remediation of risks and findings, audit programmes (`workpackage/type`, status, due date) |
| ImplementationDeliverable | For the results of work packages: documents, systems, process changes, evidence (`deliverable/type`) |
| ImplementationEvent | For milestones, go-lives and deadlines (`event/type`) |
| ImplementationPlateau | For a state of the architecture: baseline, transition, target (`plateau/type`) |
| ImplementationGap | For the difference between two plateaus (`gap/status`, `gap/impact`) |

**Migration path:** Plateau "Baseline" → triggers → Plateau "Target"; Gap → compares → both plateaus; Work Package → realizes → Deliverable → realizes → Plateau "Target"; Gap → closedBy → Work Package.

**Platform migration:** a plateau `contains` the technology elements of its state: `technologyServices`, `technologySystemSoftware`, `technologyNodes` and (optionally) `technologyArtifacts`, next to application components and requirements. Model the past, current and target platform as three plateaus chained with `triggers`, with a Gap per step; the plateau page lists what it contains, the technology element shows (reverse lookup) in which plateaus it appears, and comparing the plateaus of a gap shows what is added or removed. See `examples/archsight/implementation/platform-migration.yaml`.

**Remediation:** Assessment "Risk" → mitigatedBy → Work Package → realizes → Deliverable (type `evidence`) → realizes → ComplianceEvidence. Group by `risk/domain` to see the plan of one domain, filter by `workpackage/status` and `workpackage/due` for what is open or late.

### Business Layer

Model **who** does **what** in business terms.

| Resource | When to Use |
|----------|-------------|
| BusinessActor | For teams, departments, or organizations |
| BusinessRole | For responsibilities held by actors: control owner, risk owner, information security officer (`role/type`) |
| BusinessProcess | For workflows that produce business value |
| BusinessProduct | For what a customer buys or contracts, as on a price list ("Online Checkout", "Premium Support") |
| BusinessControl | For controls that guide a process (access review, change approval), with an owner and executors |
| BusinessEvent | For things that happen in the business: threat events, loss events, incidents, triggers (`event/type`) |

**Example chain:** Process "Incident Response" → performedBy → Actor "Platform Team"; Process "Incident Response" → servedBy → Service "Monitoring"

**Roles:** Process "Incident Response" → performedBy → Role "Incident Manager" → performedBy → Actor "Platform Team". Controls, risks, policies and work packages use `ownedBy` (and controls `executedBy`) the same way. Use a role where the responsibility has a name of its own and should survive a change of team; pointing straight at an actor stays valid.

**Controls:** Process "Incident Response" → guidedBy → Control "Escalation Review" → ownedBy / executedBy → Role or Actor. How controls, requirements and evidence fit together is described under Relation Patterns below.

### Application Layer

Model **software** that supports the business.

| Resource | When to Use |
|----------|-------------|
| ApplicationService | For behaviour software offers to a consumer, named by its function ("Payment Authorization", "Document Search") |
| ApplicationComponent | For what is built, deployed and versioned, by runtime role ("Payments:API", "Payments:Worker") |
| ApplicationInterface | For APIs and integration points |
| DataObject | For data structures and schemas |

**Example chain:** Service "Payment Authorization" → realizedThrough → Component "Payments:API" → exposes → Interface "Payments:RestAPI"

#### Classifying components

Components are not all alike: some are run, some are only imported, some bundle both. Say which with `component/type`
(`executable`, `library`, `module`, `plugin`, `frontend`, `other`) and, for executables and plugins, what they do with
`component/role` (`service`, `cli`, `job`, `operator`, `agent`). Importers set `component/type` and add machine tags
(`namespace:value`, such as `ecosystem:go`, `packaging:go-module`, `linkage:shared`) to the regular
`architecture/tags` from the manifests; the tags a person set stay, and a re-import only replaces the machine tags of
those namespaces. The entry points (main packages such as `cmd/api`) are written to `component/entrypoints`, a list
you query like a tag (`component/entrypoints == "cmd/api"`) that is not a sidebar filter, because there are too many
distinct values. `component/role` is set by hand and never overwritten. A generated component is named after its module path (`github.com/alice/shop` → `alice:shop`). When
two repositories declare the same module path (a prototype and its successor, a fork), each gets its own component:
the repository the module path names keeps the plain name (`github.com/acme/library` names `Repo:acme:library`),
then the one that is not archived, then the first by name; the other gets its repository appended
(`alice:shop@acme:shop-prototype`), and a dependency on the module path points at the plain name. A `go.mod` in a
subdirectory whose module path names another known repository is a copy of that repository's module and gets no
component at all. Neither does a nested `go.mod` below a test, tool, example or benchmark directory (`test/e2e`,
`tools`, `hack`, `examples/foo`, `internal/systemtest`): nothing realizes such code or depends on it, so its packages
only appear in the repository's module graph; `cmd/<name>/go.mod` stays a component. The importer only sees the other repository once both were imported, so the names separate on the
import after that; until then `archsight lint` warns about the merged component. A hand-written component that lists
several repositories is left as it is. The computed `component/dependents` counts the components that depend on a
component, which shows how widely a library or module is shared.

| Ecosystem | Executable | Library | Module (bundles both) |
|-----------|------------|---------|-----------------------|
| Go | `package main` (`component/entrypoints`: one per main package) | no `main` package | main packages plus importable packages outside `internal/` and `cmd/` |
| JavaScript, TypeScript | `bin`, a server entry point | `main`, `exports`, `types` | `workspaces` root |
| Ruby | gemspec `executables`, Rails app | gem without executables | monorepo of gems |
| Python | `[project.scripts]`, `__main__.py` | package published to an index | distribution of several packages |
| Rust | `[[bin]]`, `src/main.rs` | `[lib]` | Cargo workspace |
| Java | `Main-Class`, Spring Boot, application plugin | plain jar | Maven or Gradle multi-module parent |
| C, C++ | `add_executable`, `bin_PROGRAMS` | `add_library`, `lib_LTLIBRARIES` (`linkage:` shared, static, header-only) | none |
| Shell, Perl | scripts (`bin/`) | `.pm` distributions, sourced files | none |

Today the Go importer sets the type of the components it generates; the other ecosystems are classified by hand until
their importers emit components. Deployable forms (container image, Helm chart, deb, rpm) are `TechnologyArtifact`s
(`artifact/type`), not component types.

### Technology Layer

Model **infrastructure** and **code**.

| Resource | When to Use |
|----------|-------------|
| TechnologyArtifact | For source code repositories, packages, images and binaries (`artifact/type`); `aggregates` its contents, nodes are `assignedTo` it |
| TechnologyService | For infrastructure services (Postgres, Redis, Kubernetes platform) |
| TechnologySystemSoftware | For logical infrastructure (database cluster, message queue) |
| TechnologyNode | For infrastructure instances; `specializes` / `composedOf` another node |
| TechnologyInterface | For technical protocols and endpoints |
| TechnologyCommunicationNetwork | For logical networks: underlay, overlay, management, public, VPN (`network/type`) |

**Example chain:** Component "Payments:API" → realizedThrough → Artifact "Repo:payments-api" → maintainedBy → Actor "Platform Team"

#### Logical Networks

Which kind to pick is in [Choosing the Kind: Infrastructure](#choosing-the-kind-infrastructure). A logical network is a `TechnologyCommunicationNetwork` (ArchiMate Communication Network). Physical links and fabrics stay
`TechnologyEquipment`; the network is what runs over them.

| From | Verb | To |
|------|------|----|
| `TechnologyCommunicationNetwork` | `composedOf` | `TechnologyCommunicationNetwork` (a metro network of its site networks) |
| `TechnologyCommunicationNetwork` | `specializes` | `TechnologyCommunicationNetwork` (concept and implementation) |
| `TechnologyCommunicationNetwork` | `servedBy` | `TechnologyCommunicationNetwork` (the network it runs over) |
| `TechnologyCommunicationNetwork` | `locatedAt` | `TechnologyFacility`, `Location` (many) |
| `TechnologyCommunicationNetwork` | `realizedBy` | `TechnologyEquipment` (the fabric), `TechnologySystemSoftware` (routing stack, VPN software) |
| `TechnologyCommunicationNetwork` | `realizedBy` | `ApplicationComponent`, `ApplicationService` (software that builds the network: an SDN agent, a network operator) |
| `TechnologyNode` | `servedBy` | `TechnologyCommunicationNetwork` |

- **Underlay and overlay:** the underlay *serves* the overlay, so the overlay is `servedBy` the underlay. A BGP-EVPN
  network that carries customer workloads is one `overlay` network served by the underlay and realized by the routing
  system software. Do not model a network per customer or tenant.
- **VPN:** a network of `network/type: vpn`, `servedBy` the network it tunnels through (usually the public network),
  `locatedAt` the sites it joins and `realizedBy` the gateway software.
- **Mesh:** `network/topology: mesh` on **one** network that is `locatedAt` all its sites. Only when single tunnels
  matter (capacity, owner) are they sub-networks, `composedOf` into the mesh.
- **Nesting and metro regions:** a network that supports a metro region is `locatedAt` the `Location` and
  `composedOf` the networks of its sites. `composedOf` and `specializes` only point at networks and must not form a
  cycle; `archsight lint` reports cycles of `composedOf`, `specializes` and `servedBy`.
- **Attachment:** a node is `servedBy` the networks it is attached to; the network page lists them.

```
# all overlay networks
TechnologyCommunicationNetwork: network/type == "overlay"

# networks that reach TechnologyFacility X
TechnologyCommunicationNetwork: -> "Facility:Madrid:DC"
```

See `examples/archsight/technology/networks.yaml`.

### Where Technology Runs

Which kind to pick is in [Choosing the Kind: Infrastructure](#choosing-the-kind-infrastructure).

Model **where** technology runs with `TechnologyFacility` (a building, data center or site, nested with `composedOf`),
`Location` (a country, metro or region) and, when the physical grouping matters, `TechnologyEquipment` (racks, fabrics,
physical clusters). Do not model sites as annotations, as one service per site, or as `TechnologyNode`s: a data
center is not a computational resource.

| Resource | When to Use |
|----------|-------------|
| Location | For a country, metro or region |
| TechnologyFacility | For a data center, colocation, office or edge site (`facility/type`), also a campus or hall inside one |
| TechnologyEquipment | Optional: racks, network fabrics, physical clusters inside a facility (`equipment/type`) |

Relations are written on the element that is placed (see [Direction of Relations](#direction-of-relations)):

| From | Verb | To |
|------|------|----|
| `TechnologyNode`, `TechnologyService`, `TechnologySystemSoftware`, `TechnologyEquipment` | `locatedAt` | `TechnologyFacility` (many) |
| `TechnologyFacility` | `locatedAt` | `Location` |
| `TechnologyFacility` | `composedOf` | `TechnologyFacility` (nested sites) |
| `TechnologyFacility` | `servedBy` | `BusinessActor` (the operator) |

`locatedAt` with many targets is the point: a service that runs in three data centers is **one** service with three
`locatedAt` relations. A `locatedAt` target that is not a TechnologyFacility (or, from a facility, a Location) is rejected by
`archsight lint`. TechnologyFacility and Location pages list what is located there (incoming `locatedAt`), grouped by kind.

A service may run on different platforms in different facilities (a managed platform in site A, a self-hosted one in
site B). There is no qualifier on the relation: locate the nodes or system software of each platform at its
facilities too, and the pair (platform, facility) is derivable.

Queries:

```
# all technology services in TechnologyFacility X
TechnologyService: -> "DC:Alpha"

# facilities that host service Y
TechnologyFacility: <- "Orders:Cluster"
```

#### Backbone and links between facilities

The physical network between sites is `TechnologyEquipment`. A **link** (fibre route, carrier circuit) is one TechnologyEquipment with
`equipment/type: link` that is `locatedAt` **both** end facilities. A **backbone** is a TechnologyEquipment that is `composedOf`
its links (composition only points at TechnologyEquipment and must not form a cycle). The logical network is a
`TechnologyService` (and routers are `TechnologyNode`s) that is `realizedBy` the TechnologyEquipment it runs over, and is
`locatedAt` the facilities it reaches:

```
TechnologyService "Network:Backbone"  --realizedBy-->  TechnologyEquipment "Equipment:Backbone"
                                                            --composedOf-->  TechnologyEquipment "Equipment:Link:Frankfurt-Madrid" (link)
                                                                                 --locatedAt-->  TechnologyFacility Frankfurt, TechnologyFacility Madrid
```

```
# all links between facilities
TechnologyEquipment: equipment/type == "link"

# links that end in TechnologyFacility X
TechnologyEquipment: equipment/type == "link" & -> "Facility:Madrid:DC"
```

The TechnologyEquipment page lists what is realized by it (incoming `realizedBy`) and the backbones it belongs to (incoming
`composedOf`). A link has no endpoints of its own: it is placed at its facilities, so keep to two `locatedAt` targets
per link. See `examples/archsight/technology/facilities.yaml`.

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
       ↓ dependsOn            (another ApplicationService)
ApplicationService
       ↓ servedBy
TechnologyService
       ↓ suppliedBy
TechnologySystemSoftware
```

A service that uses another one says so with `dependsOn` on the service, the same verb components use between each
other. Do not add the other service's components to your own `realizedThrough`: the component would then belong to
two services, its owner is ambiguous and every rollup over the service's components counts it twice. Two services may
depend on each other, so `dependsOn` is exempt from the cycle check. In `examples/archsight`, "Refunds" depends on "Payment Authorization" (it refunds an authorized payment) and
"Payment Authorization" depends on "Refunds" (it asks to reverse a payment it cannot complete).

### Concept and Implementation

One technology *concept* often has several *implementations*: a "regional cluster" is implemented by a hypervisor
platform on some sites and by bare metal on others. Model the concept as an element and let every implementation
**specialize** it (ArchiMate specialization). The specialization is written on the specific element and always points
to an element of the **same kind**:

| Kind | Verb | Target | ArchiMate |
|------|------|--------|-----------|
| `TechnologyNode` | `specializes` | `TechnologyNode` | specialization |
| `TechnologySystemSoftware` | `specializes` | `TechnologySystemSoftware` | specialization |
| `TechnologyService` | `specializes` | `TechnologyService` | specialization |
| `TechnologyNode` | `composedOf` | `TechnologyNode` | composition (a cluster made of hosts) |
| `TechnologySystemSoftware` | `composedOf` | `TechnologySystemSoftware` | composition (a platform bundles components) |

```yaml
kind: TechnologyNode
metadata:
  name: Tech:RegionalCluster          # the concept
spec: {}
---
kind: TechnologyNode
metadata:
  name: Tech:RegionalCluster:Hypervisor   # one implementation
spec:
  specializes:
    technologyNodes:
      - Tech:RegionalCluster
  composedOf:
    technologyNodes:
      - Tech:RegionalCluster:Host
```

The page of the concept shows the implementations as incoming `specializes`, the implementation shows what it
`specializes`. A target of another kind is rejected when the resources are loaded, and `archsight lint` reports a
`specializes` or `composedOf` chain that leads back to where it started. Do not use `realizedBy` between elements of
one kind: realization goes from concrete to abstract across layers. See `examples/archsight/technology/platforms.yaml`.

### Deployment

An artifact (`TechnologyArtifact`) describes what reaches a host; three relations connect it to the rest:

| Kind | Verb | Target | ArchiMate | Meaning |
|------|------|--------|-----------|---------|
| `TechnologyArtifact` | `aggregates` | `TechnologyArtifact` | aggregation | an image contains packages, a chart references container images |
| `TechnologyNode` | `assignedTo` | `TechnologyArtifact` | assignment | the artifact is deployed on the node |
| `TechnologySystemSoftware` | `assignedTo` | `TechnologyArtifact` | assignment | the artifact is executed by the system software |

`assignedTo` is written on the node or system software, which owns the deployment. A bootable OS image, VM template or
disk image is an artifact of `artifact/type: image` (`binary` and `archive` exist as well).

```
ApplicationComponent
       ↓ realizedThrough       (what the component is built from)
TechnologyArtifact (image)
       ↓ aggregates            (what the image contains)
TechnologyArtifact (package)

TechnologyNode
       ↓ assignedTo            (where the artifact is deployed)
TechnologyArtifact
```

The artifact's page shows `aggregates` as incoming "contained in" and `assignedTo` as incoming "deployed on"; the node's
page shows what it `assignedTo`. This answers "which hosts get package X" with a reverse lookup instead of a package list in
an annotation. `archsight lint` reports an `aggregates` chain that leads back to where it started. Example: a host role
boots an image that contains two packages, and configuration management installs a third on the same hosts, see
`examples/archsight/technology/deployment.yaml`. Do not use `servedBy` between artifacts for contents: it reads as
"is served by", not "contains".


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
| Control objective | `MotivationGoal` | `goal/type: control-objective` | the risk is `mitigatedBy` it |
| Control measure | `MotivationRequirement` | `requirement/type: control-measure` | a goal `realizes` it; the risk can be `mitigatedBy` it |
| Control implementation | `BusinessControl`, applications, nodes, processes | none | `satisfies` / `realizes` the measure |
| Proof of the control | `ComplianceEvidence` | `evidence/type` | `evidence/status: not-applicable` where the requirement does not apply |
| Asset at risk | any application, technology, data or process kind | `asset/value`, `asset/confidentiality`, `asset/integrity`, `asset/availability` | the protection need (BSI Schutzbedarf) |
| Policy (design level) | `MotivationPrinciple` | `principle/type: security-policy` or `risk-policy` | status, validity, framework mapping |
| Operational policy, regulation | `MotivationConstraint` | none | the paper has no element for operational policy |
| Risk domain | none; annotation `risk/domain` | `risk/domain`, `risk/category` | group by it with a query or a `View` |

The chain, as in the paper's Coldhard Steel example:

```
MotivationDriver (threat) ──influences──→ MotivationAssessment (risk) ──mitigatedBy──→ MotivationGoal (control objective)
        │ triggers                                  │ assesses                                      │ realizes
        ↓                                           ↓                                               ↓
BusinessEvent (loss event) ←──influences── MotivationAssessment (vulnerability)      MotivationRequirement (control measure)
        ↑ triggers                                                                                  ↑ satisfies / realizes
TechnologyEvent / ApplicationEvent (threat event, attack)                         BusinessControl / asset ──evidencedBy──→ ComplianceEvidence
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
  ownedBy: { businessRoles: [Role:RiskOwner] }
  assesses: { technologyNodes: [Node:Web1] }
  mitigatedBy: { goals: [Objective:ReduceExposure], businessControls: [Control:FirewallReview] }
---
kind: MotivationGoal
metadata: { name: Objective:ReduceExposure, annotations: { goal/type: control-objective } }
spec:
  realizes: { motivationRequirements: [Measure:Firewall] }
---
kind: MotivationRequirement
metadata: { name: Measure:Firewall, annotations: { requirement/type: control-measure } }
spec: {}
---
kind: BusinessControl
metadata: { name: Control:FirewallReview }
spec:
  ownedBy: { businessRoles: [Role:ControlOwner] }
  satisfies: { motivationRequirements: [Measure:Firewall] }
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

### Lifecycle

`lifecycle/status` marks any resource with `architecture/*` annotations (products, components, services, artifacts, ...) as
`active`, `deprecated` (do not start new uses), `sunset` (being phased out) or `end-of-life` (no longer operated or
supported). A missing annotation means `active`. The status shows as a badge (yellow for `deprecated`, red for `sunset` and
`end-of-life`) and is a sidebar filter and query term (`lifecycle/status == "deprecated"`).

| Annotation | Purpose |
|------------|---------|
| `lifecycle/status` | The state above |
| `lifecycle/deprecatedAt`, `lifecycle/sunsetAt`, `lifecycle/endOfLifeAt` | When it happened or will happen (ISO 8601 date or time, checked by `archsight lint`) |
| `lifecycle/replacedBy` | The resource that replaces it: a name for a resource of the same kind, `Kind/Name` for another kind (a component replaced by an `ApplicationService/...`). Shown as a link, `archsight lint` checks that it exists |
| `lifecycle/reason` | Why, in markdown |

```yaml
kind: ApplicationService
metadata:
  name: LegacyExport
  annotations:
    lifecycle/status: sunset
    lifecycle/sunsetAt: 2027-03-31
    lifecycle/replacedBy: ApplicationService/ExportV2
```

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
