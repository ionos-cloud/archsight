# frozen_string_literal: true

# ApplicationService represents the high level application service that implements capabilities
class Archsight::Resources::ApplicationService < Archsight::Resources::Base
  include_annotations :git, :architecture, :generated, :backup

  description <<~MD
    Represents a high-level application service that implements business capabilities.

    ## ArchiMate Definition

    **Layer:** Application
    **Aspect:** Behavior

    An application service represents an explicitly defined exposed application behavior.
    It is the externally visible functionality provided by application components, grouping
    multiple components that work together to deliver business value.

    ## Usage

    Use ApplicationService to represent:

    - Complete product offerings (ManagedKubernetes, DBaaS PostgreSQL)
    - Logical groupings of application components
    - Services exposed to business processes
    - APIs and their implementations as a cohesive unit
  MD

  icon "cube"
  layer "application"

  # Service plane classification
  annotation "architecture/plane",
             description: "Service plane classification (control manages resources, data handles traffic)",
             title: "Service Plane",
             enum: %w[control data],
             list: true

  # Computed Annotations
  computed_annotation "repository/artifacts/total",
                      title: "Total Git Repositories",
                      description: "Number of related git repositories",
                      type: Integer do
    count(outgoing_transitive('TechnologyArtifact: artifact/type == "repo"'))
  end

  computed_annotation "repository/artifacts/active",
                      title: "Active Git Repositories",
                      description: "Number of active git repositories",
                      type: Integer do
    count(outgoing_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "active"'))
  end

  computed_annotation "repository/artifacts/abandoned",
                      title: "Abandoned Git Repositories",
                      description: "Number of abandoned git repositories",
                      type: Integer do
    count(outgoing_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "abandoned"'))
  end

  computed_annotation "repository/artifacts/highBusFactor",
                      title: "High Bus Factor Repositories",
                      description: "Number of active git repositories with high bus factor",
                      type: Integer do
    count(outgoing_transitive('TechnologyArtifact: artifact/type == "repo" & activity/busFactor == "high"'))
  end

  computed_annotation "repository/artifacts/archived",
                      title: "Archived Repositories",
                      description: "Number of archived git repositories",
                      type: Integer do
    count(outgoing_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "archived"'))
  end

  %w[scc/estimatedCost scc/estimatedScheduleMonths scc/estimatedPeople].each do |anno_key|
    computed_annotation anno_key,
                        title: "Total #{anno_key.split("/").last.split(/(?=[A-Z])/).map(&:capitalize).join(" ")}",
                        description: "Total estimated #{anno_key.split("/").last} from related repositories",
                        type: Integer do
      sum(outgoing_transitive('TechnologyArtifact: artifact/type == "repo"'), anno_key)
    end
  end

  computed_annotation "scc/languages",
                      title: "Primary Languages",
                      list: true,
                      description: "Top 4 programming languages by lines of code across related artifacts",
                      filter: :list,
                      sidebar: true do
    collect(outgoing_transitive(:ApplicationComponent), "scc/language")
  end

  computed_annotation "activity/commits",
                      title: "Monthly Commits",
                      description: "Accumulated monthly commit counts across all related application components",
                      sidebar: false do
    components = outgoing_transitive(:ApplicationComponent)
    next nil if components.empty?

    # Collect all commit arrays from components (they all end at the current month)
    # Use get() to trigger computation of computed annotations on ApplicationComponents
    commit_arrays = components.map do |component|
      commits_str = get(component, "activity/commits")
      next nil if commits_str.nil? || commits_str.empty?

      commits_str.split(",").map(&:to_i)
    end.compact

    next nil if commit_arrays.empty?

    # Find the maximum length (oldest component determines the timeline)
    max_length = commit_arrays.map(&:length).max

    # Pad shorter arrays at the beginning with zeros and sum
    result = Array.new(max_length, 0)
    commit_arrays.each do |arr|
      offset = max_length - arr.length
      arr.each_with_index do |count, idx|
        result[offset + idx] += count
      end
    end

    result.join(",")
  end

  computed_annotation "activity/createdAt",
                      title: "Created",
                      description: "Earliest repository creation date across all related application components",
                      type: Time do
    components = outgoing_transitive(:ApplicationComponent)
    next nil if components.empty?

    # Use get() to trigger computation of computed annotations on ApplicationComponents
    dates = components.map do |component|
      date_val = get(component, "activity/createdAt")
      next nil if date_val.nil?

      if date_val.is_a?(Time)
        date_val
      else
        begin
          Time.parse(date_val.to_s)
        rescue StandardError
          nil
        end
      end
    end.compact

    dates.min
  end

  computed_annotation "activity/contributors",
                      title: "Monthly Contributors",
                      description: "Accumulated monthly unique contributor counts across all related application components",
                      sidebar: false do
    components = outgoing_transitive(:ApplicationComponent)
    next nil if components.empty?

    # Collect all contributor arrays from components (they all end at the current month)
    # Use get() to trigger computation of computed annotations on ApplicationComponents
    contrib_arrays = components.map do |component|
      contrib_str = get(component, "activity/contributors")
      next nil if contrib_str.nil? || contrib_str.empty?

      contrib_str.split(",").map(&:to_i)
    end.compact

    next nil if contrib_arrays.empty?

    # Find the maximum length (oldest component determines the timeline)
    max_length = contrib_arrays.map(&:length).max

    # Pad shorter arrays at the beginning with zeros and sum
    result = Array.new(max_length, 0)
    contrib_arrays.each do |arr|
      offset = max_length - arr.length
      arr.each_with_index do |count, idx|
        result[offset + idx] += count
      end
    end

    result.join(",")
  end

  computed_annotation "activity/contributors/6m",
                      title: "Contributors (6 months)",
                      description: "Sum of unique contributors in the last 6 months across related components",
                      type: Integer do
    components = outgoing_transitive(:ApplicationComponent)
    next nil if components.empty?

    # Sum unique contributor counts from related components
    total = components.sum do |component|
      get(component, "activity/contributors/6m").to_i
    end
    total.positive? ? total : nil
  end

  computed_annotation "activity/contributors/total",
                      title: "Contributors (total)",
                      description: "Sum of unique contributors across related components",
                      type: Integer do
    components = outgoing_transitive(:ApplicationComponent)
    next nil if components.empty?

    # Sum unique contributor counts from related components
    total = components.sum do |component|
      get(component, "activity/contributors/total").to_i
    end
    total.positive? ? total : nil
  end

  relation :realizedThrough, :applicationComponents, :ApplicationComponent
  relation :servedBy, :businessActors, :BusinessActor
  relation :servedBy, :technologyServices, :TechnologyService
  relation :realizes, :businessConstraints, :BusinessConstraint
  relation :realizes, :businessRequirements, :BusinessRequirement
  relation :partiallyRealizes, :businessRequirements, :BusinessRequirement
  relation :plans, :businessRequirements, :BusinessRequirement
  relation :realizes, :dataObjects, :DataObject
  relation :evidencedBy, :complianceEvidences, :ComplianceEvidence
end
