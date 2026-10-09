# frozen_string_literal: true

# BusinessRole represents a responsibility that actors take on
class Archsight::Resources::BusinessRole < Archsight::Resources::Base
  include_annotations :git, :architecture, :risk

  description <<~MD
    Represents the responsibility for performing specific behavior, to which an actor can be assigned.

    ## ArchiMate Definition

    **Layer:** Business
    **Aspect:** Active Structure

    A business role is the responsibility for performing specific behavior, to which an actor can be assigned. The
    role is what a process, a control or a risk refers to; the actor (a team) holds the role. Changing who holds the
    role changes it everywhere it is used.

    ## Usage

    Use BusinessRole to represent:

    - Roles of an ISMS: information security officer, data protection officer, control owner, control executor,
      risk owner
    - Roles in a process (incident manager, release approver)
    - Any responsibility that should not be tied to one team by name

    ## How it connects

    The responsibility edges point down to the role, and the role points down to the actor that holds it:

    ```
    BusinessProcess ──performedBy──▶ BusinessRole ──performedBy──▶ BusinessActor
    BusinessControl ──ownedBy / executedBy──▶ BusinessRole
    ```

    - A `BusinessProcess` is `performedBy` the role, a `BusinessControl` is `ownedBy` and `executedBy` it
    - Assessments, principles, work packages, deliverables and implementation events are `ownedBy` it
    - The role is `performedBy` the actors that hold it
    - Pointing straight at an actor stays valid; use a role where the responsibility has a name of its own

    ## Security and risk modelling

    Roles carry the accountability of the ISMS: the owner and executor roles of controls (BSI C5, ITGS), the owner of
    a risk, the issuer of a policy. Use `role/type` to tell owners, executors and officers apart and `risk/domain`
    to group roles by context.
  MD

  icon "user-badge-check"
  layer "business"

  annotation "role/id",
             description: "Identifier of the role in its list (e.g. ISB, DPO)",
             title: "Role ID",
             summary: true

  annotation "role/type",
             description: "What kind of responsibility the role is (specialization of the role)",
             enum: %w[owner executor officer reviewer operator other],
             filter: :word,
             summary: true

  annotation "role/scope",
             description: "What the role is responsible for, in a short paragraph",
             title: "Scope",
             format: :markdown

  relation :performedBy, :businessActors, :BusinessActor
end
