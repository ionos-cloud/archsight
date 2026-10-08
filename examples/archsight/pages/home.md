---
title: Home
tags: howto
author: Vincent Landgraf <vincent.landgraf@ionos.com>
owner: Vincent Landgraf <vincent.landgraf@ionos.com>
status: approved
toc: yes
---

Archsight turns a directory of YAML files into a browsable, queryable model of your architecture.
Resources are inspired by [ArchiMate](/doc/archimate), the structure follows [TOGAF](/doc/togaf), and the
result is served as a web UI, a REST API and an MCP server.

## Five minutes

```bash
# 1. Start the web UI on the bundled example
bundle exec archsight web -r examples/archsight

# 2. Check your own resources
bundle exec archsight lint -r path/to/resources

# 3. Generate a YAML skeleton for a new resource
bundle exec archsight template ApplicationComponent
```

Open <http://localhost:4567>. Edit a YAML or markdown file and press **Reload** in the UI.

## Where to go next

| I want to... | Read |
|--------------|------|
| Understand the vocabulary | [[Core Concepts]] |
| Model a system | [[Modeling Guide]] |
| Find things | [[Searching and Queries]] |
| Write documentation like this page | [[Writing Pages]] |
| Draw diagrams | [[Diagrams in Pages]] |
| Fill the model from GitLab, GitHub or git | [[Importing Data]] |
| Deploy it | [[Running Archsight]] |
| Understand how Archsight itself is built | [[Archsight Architecture]] |
| Use it from an AI assistant or a script | [[MCP and REST API]] |

## Directory layout

Archsight loads every `.yaml` and every `.md` file with frontmatter below the resources directory.
The layout is free, the bundled example groups by layer:

```text
examples/archsight/
├── strategy/      StrategyCapability
├── motivation/    MotivationStakeholder, MotivationGoal, MotivationOutcome, MotivationRequirement, MotivationConstraint
├── business/      BusinessProduct, BusinessProcess
├── components/    ApplicationComponent
├── interfaces/    ApplicationInterface
├── technology/    TechnologyService, TechnologyArtifact
├── teams/         BusinessActor
├── compliance/    ComplianceEvidence
├── imports/       Import (generate resources from external systems)
├── analyses/      Analysis (Ruby scripts run against the model)
├── views/         View (saved queries)
└── pages/         Page + PageMenu (this handbook)
```
