# frozen_string_literal: true

# BusinessProduct represents a product or service offered to customers
class Archsight::Resources::BusinessProduct < Archsight::Resources::Base
  include_annotations :git, :architecture

  description <<~MD
    Represents a coherent collection of services offered to customers.

    ## ArchiMate Definition

    **Layer:** Business
    **Aspect:** Passive Structure

    A product represents a coherent collection of services and/or passive structure elements,
    accompanied by a contract/set of agreements, which is offered as a whole to customers.
    Products are the marketable offerings that deliver value.

    ## Usage

    Use BusinessProduct to represent:

    - Cloud services (Compute, Storage, Networking)
    - Managed database offerings
    - Kubernetes services
    - Enterprise support packages
    - API products
  MD

  icon "box-iso"
  layer "business"

  computed_annotation "repository/artifacts/total",
                      title: "Total Git Repositories",
                      description: "Number of related git repositories across all related application components",
                      type: Integer do
    sum(outgoing_transitive(:ApplicationService), "repository/artifacts/total")
  end

  computed_annotation "repository/artifacts/active",
                      title: "Active Git Repositories",
                      description: "Number of related git repositories across all related application components",
                      type: Integer do
    sum(outgoing_transitive(:ApplicationService), "repository/artifacts/active")
  end

  computed_annotation "repository/artifacts/abandoned",
                      title: "Abandoned Git Repositories",
                      description: "Number of related git repositories across all related application components",
                      type: Integer do
    sum(outgoing_transitive(:ApplicationService), "repository/artifacts/abandoned")
  end

  computed_annotation "repository/artifacts/highBusFactor",
                      title: "High Bus Factor Repositories",
                      description: "Number of active git repositories with high bus factor across all related application components",
                      type: Integer do
    sum(outgoing_transitive(:ApplicationService), "repository/artifacts/highBusFactor")
  end

  computed_annotation "repository/artifacts/archived",
                      title: "Archived Repositories",
                      description: "Number of archived git repositories across all related application services",
                      type: Integer do
    sum(outgoing_transitive(:ApplicationService), "repository/artifacts/archived")
  end

  %w[scc/estimatedCost scc/estimatedScheduleMonths scc/estimatedPeople].each do |anno_key|
    computed_annotation anno_key,
                        title: "Total #{anno_key.split("/").last.split(/(?=[A-Z])/).map(&:capitalize).join(" ")}",
                        description: "Total estimated #{anno_key.split("/").last} from related artifacts across all related application components",
                        type: Integer do
      sum(outgoing_transitive(:ApplicationService), anno_key)
    end
  end

  computed_annotation "activity/commits",
                      title: "Monthly Commits",
                      description: "Accumulated monthly commit counts across all related application services",
                      sidebar: false do
    services = outgoing_transitive(:ApplicationService)
    next nil if services.empty?

    # Collect all commit arrays from services (they all end at the current month)
    # Use get() to trigger computation of computed annotations on ApplicationServices
    commit_arrays = services.map do |service|
      commits_str = get(service, "activity/commits")
      next nil if commits_str.nil? || commits_str.empty?

      commits_str.split(",").map(&:to_i)
    end.compact

    next nil if commit_arrays.empty?

    # Find the maximum length (oldest service determines the timeline)
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
                      description: "Earliest repository creation date across all related application services",
                      list: true,
                      type: Time do
    services = outgoing_transitive(:ApplicationService)
    next nil if services.empty?

    # Use get() to trigger computation of computed annotations on ApplicationServices
    dates = services.map do |service|
      date_val = get(service, "activity/createdAt")
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
                      description: "Accumulated monthly unique contributor counts across all related application services",
                      sidebar: false do
    services = outgoing_transitive(:ApplicationService)
    next nil if services.empty?

    # Collect all contributor arrays from services (they all end at the current month)
    # Use get() to trigger computation of computed annotations on ApplicationServices
    contrib_arrays = services.map do |service|
      contrib_str = get(service, "activity/contributors")
      next nil if contrib_str.nil? || contrib_str.empty?

      contrib_str.split(",").map(&:to_i)
    end.compact

    next nil if contrib_arrays.empty?

    # Find the maximum length (oldest service determines the timeline)
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
                      description: "Sum of unique contributors in the last 6 months across related services",
                      list: true,
                      type: Integer do
    services = outgoing_transitive(:ApplicationService)
    next nil if services.empty?

    # Sum unique contributor counts from related services
    total = services.sum do |service|
      get(service, "activity/contributors/6m").to_i
    end
    total.positive? ? total : nil
  end

  computed_annotation "activity/contributors/total",
                      title: "Contributors (total)",
                      description: "Sum of unique contributors across related services",
                      type: Integer do
    services = outgoing_transitive(:ApplicationService)
    next nil if services.empty?

    # Sum unique contributor counts from related services
    total = services.sum do |service|
      get(service, "activity/contributors/total").to_i
    end
    total.positive? ? total : nil
  end

  relation :realizes, :strategyCapabilities, :StrategyCapability
  relation :realizes, :businessConstraints, :BusinessConstraint
  relation :realizes, :businessRequirements, :BusinessRequirement
  relation :servedBy, :businessActors, :BusinessActor
  relation :servedBy, :applicationServices, :ApplicationService
  relation :exposes, :applicationInterfaces, :ApplicationInterface
  relation :provides, :complianceEvidences, :ComplianceEvidence
end
