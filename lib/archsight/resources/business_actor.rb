# frozen_string_literal: true

# BusinessActor represents teams or organizational units
class Archsight::Resources::BusinessActor < Archsight::Resources::Base
  include_annotations :git, :architecture, :generated

  description <<~MD
    Represents a team, organizational unit, or external entity that performs business behavior.

    ## ArchiMate Definition

    **Layer:** Business
    **Aspect:** Active Structure

    A business actor represents a business entity that is capable of performing behavior.
    Actors can be individuals, teams, departments, or external organizations that participate
    in business processes or own/maintain system components.

    ## Usage

    Use BusinessActor to represent:

    - Development teams
    - Operations teams
    - External vendors or partners
    - Support organizations
    - Cross-functional groups
  MD

  icon "community"
  layer "business"

  annotation "team/lead",
             description: 'Team lead (format: "Name <email>" or "email")',
             title: "Team Lead",
             sidebar: false,
             filter: :word,
             format: :tag_word,
             type: Archsight::Annotations::EmailRecipient

  annotation "team/members",
             description: 'Team members (format: "Name <email>" or "email")',
             title: "Team Members",
             sidebar: false,
             filter: :list,
             format: :multiline,
             type: Archsight::Annotations::EmailRecipient

  annotation "team/jira",
             description: "Jira project keys for issue tracking (primary queue first)",
             title: "Jira Projects",
             sidebar: false,
             filter: :list,
             format: :tag_list

  annotation "jira/issues/created",
             description: "Issues created per month (comma-separated, last 6 months)",
             title: "Issues Created",
             sidebar: false

  annotation "jira/issues/resolved",
             description: "Issues resolved per month (comma-separated, last 6 months)",
             title: "Issues Resolved",
             sidebar: false

  # ITIL 4 General Management Practices
  annotation "itil/general",
             description: "ITIL general management practices",
             title: "ITIL General Practices",
             filter: :list,
             format: :tag_list,
             enum: %w[
               strategy-management portfolio-management architecture-management
               risk-management workforce-management continual-improvement
               knowledge-management measurement-reporting change-management
               project-management relationship-management supplier-management
               financial-management
             ]

  # ITIL 4 Service Management Practices
  annotation "itil/service",
             description: "ITIL service management practices",
             title: "ITIL Service Practices",
             filter: :list,
             format: :tag_list,
             enum: %w[
               service-design service-catalog service-level-management
               availability-management capacity-management continuity-management
               security-management configuration-management
             ]

  # ITIL 4 Technical Management Practices
  annotation "itil/technical",
             description: "ITIL technical management practices",
             title: "ITIL Technical Practices",
             filter: :list,
             format: :tag_list,
             enum: %w[
               deployment-management infrastructure-management software-development
               release-management change-enablement service-validation
               incident-management problem-management service-desk
               monitoring-management
             ]

  relation :compositeOf, :businessActors, :BusinessActor

  # Computed Annotations
  computed_annotation "team/size",
                      title: "Team Size",
                      description: "Number of team members (including sub-teams)",
                      list: true,
                      type: Integer do
    # Count members from this team
    members = @instance.annotations["team/members"]
    count = if members.nil? || members.empty?
              0
            else
              members.split(/[,\n]/).map(&:strip).reject(&:empty?).size
            end

    # Add members from sub-teams (teams that are composites of this team)
    incoming_transitive(:BusinessActor).each do |subteam|
      subteam_members = subteam.annotations["team/members"]
      next if subteam_members.nil? || subteam_members.empty?

      count += subteam_members.split(/[,\n]/).map(&:strip).reject(&:empty?).size
    end

    count
  end

  computed_annotation "team/lead/size",
                      title: "Team Leads",
                      description: "Number of team leads (including sub-teams)",
                      type: Integer do
    # Count lead from this team
    count = @instance.annotations["team/lead"] ? 1 : 0

    # Add leads from sub-teams
    incoming_transitive(:BusinessActor).each do |subteam|
      count += 1 if subteam.annotations["team/lead"]
    end

    count
  end

  computed_annotation "repository/artifacts/total",
                      title: "Maintained Repositories",
                      description: "Number of git repositories maintained by this team",
                      type: Integer do
    count(incoming_transitive('TechnologyArtifact: artifact/type == "repo"'))
  end

  computed_annotation "repository/artifacts/active",
                      title: "Active Repositories",
                      description: "Number of active git repositories maintained by this team",
                      type: Integer do
    count(incoming_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "active"'))
  end

  computed_annotation "repository/artifacts/highBusFactor",
                      title: "High Bus Factor Repositories",
                      description: "Number of active git repositories with high bus factor maintained by this team",
                      type: Integer do
    count(incoming_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "active" & activity/busFactor == "high"'))
  end

  computed_annotation "repository/artifacts/abandoned",
                      title: "Abandoned Repositories",
                      description: "Number of abandoned git repositories maintained by this team",
                      type: Integer do
    count(incoming_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "abandoned"'))
  end

  computed_annotation "repository/artifacts/archived",
                      title: "Archived Repositories",
                      description: "Number of archived git repositories maintained by this team",
                      type: Integer do
    count(incoming_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "archived"'))
  end

  computed_annotation "jira/projectUrl",
                      title: "Jira Board",
                      description: "Link to Jira board (computed from team/jira)",
                      format: :link do
    jira_key = @instance.annotations["team/jira"]
    next nil if jira_key.nil? || jira_key.empty?

    # Use first key if multiple (comma/newline separated)
    primary_key = jira_key.split(/[,\n]/).first&.strip
    next nil if primary_key.nil? || primary_key.empty?

    "https://jira.example.com/projects/#{primary_key}/issues"
  end
end
