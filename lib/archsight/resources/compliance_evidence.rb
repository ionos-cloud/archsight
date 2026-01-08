# frozen_string_literal: true

# ComplianceEvidence represents proof of compliance with requirements
class Archsight::Resources::ComplianceEvidence < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents documentation or artifacts that demonstrate compliance with requirements.

    ## ArchiMate Definition

    **Layer:** Implementation & Migration
    **Aspect:** Passive Structure

    Compliance evidence represents tangible proof that a system or process meets specific
    requirements. It bridges the gap between stated requirements and their actual
    implementation in the architecture.

    ## Usage

    Use ComplianceEvidence to represent:

    - Audit reports
    - Security certifications
    - Test results and reports
    - Configuration documentation
    - Process documentation
  MD

  icon "shield-check"
  layer "business"

  annotation "evidence/type",
             description: "Type of evidence",
             enum: %w[documentation process configuration audit-log technical-control]

  annotation "evidence/status",
             description: "Current status of evidence",
             enum: %w[implemented partial not-implemented]

  relation :satisfies, :businessRequirements, :BusinessRequirement
end
