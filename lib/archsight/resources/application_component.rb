# frozen_string_literal: true

# ApplicationComponent a part of the ApplicationService
class Archsight::Resources::ApplicationComponent < Archsight::Resources::Base
  include_annotations :git, :architecture, :generated, :backup

  description <<~MD
    Represents a logical part of an application service that can be deployed independently.

    ## ArchiMate Definition

    **Layer:** Application
    **Aspect:** Active Structure

    An application component represents an encapsulation of application functionality aligned
    with implementation structure. Components represent the deployable units that together
    form a service.

    ## Usage

    Use ApplicationComponent to represent:

    - Microservices (api-server, worker, scheduler)
    - Backend components
    - Frontend applications
    - Background workers
  MD

  icon "component"
  layer "application"

  # Architecture
  annotation "architecture/kind",
             description: "Architecture pattern or style",
             title: "Architecture Kind",
             enum: %w[3-tier hexagonal kubernetes-operator]
  annotation "architecture/size",
             description: "Architecture size classification",
             title: "Architecture Size",
             enum: %w[microservice monolith]

  # Availability
  annotation "availability/quality",
             description: "Service availability quality target per year",
             title: "Availability",
             enum: ["no goal", "99.5", "99.95", "99.995", "99.9995"]

  # Frontend
  annotation "frontend/responsiveness",
             description: "Frontend 99th percentile responsiveness target",
             title: "Frontend Responsiveness (99p)",
             enum: %w[10ms 100ms 1000ms 2s 5s 10s unresponsive]

  # Persistence
  annotation "persistence/provider",
             description: "Persistence provider type",
             title: "Persistence Provider",
             enum: %w[self-hosted managed-service]
  annotation "persistence/confidential",
             description: "Persistence data confidentiality level",
             title: "Persistence Confidentiality",
             enum: %w[none simple-full-disk per-customer-key rotated-per-customer-key customer-provided-key]
  annotation "persistence/failover",
             description: "Persistence failover configuration",
             title: "Persistence Failover",
             enum: %w[none cold-standby hot-standby]

  # Audit
  annotation "audit/logging",
             description: "Audit logging destination",
             title: "Audit Logging",
             filter: :word
  annotation "audit/activity",
             description: "Audit activity reliability",
             title: "Audit Activity",
             enum: %w[reliable unreliable]

  # Security
  annotation "security/handling",
             description: "Security credential handling approach",
             title: "Security Handling",
             enum: ["none", "static-tokens", "revokable", "dynamic-tokens", "work/identity separation"]
  annotation "security/kill-switch",
             description: "Security kill-switch capability",
             title: "Security Kill Switch",
             filter: :word

  # Abuse
  annotation "abuse/query",
             description: "Abuse query mechanism",
             title: "Abuse Query",
             enum: %w[none manual api]
  annotation "abuse/response",
             description: "Abuse response mechanism",
             title: "Abuse Response",
             enum: %w[none manual api]

  # Lawful Interception
  annotation "lawful/interception",
             description: "Lawful interception handling capability",
             title: "Lawful Interception",
             enum: %w[none manual api]

  # Configuration
  annotation "config/handling",
             description: "Configuration handling approach",
             title: "Config Handling",
             enum: ["no configuration", "configuration via file unencrypted secrets",
                    "config via ENV encrypted secrets"]

  # Fault Tolerance
  annotation "faultTolerance/quality",
             description: "Fault tolerance quality level",
             title: "Fault Tolerance",
             enum: ["no fault tolerance", "survive server failure", "survive rack failure", "survive DC failure",
                    "regional architecture"]

  # Supportability
  annotation "supportability/quality",
             description: "Supportability quality level",
             title: "Supportability",
             enum: ["no support", "support by dev", "support by ops", "support by api",
                    "self service support via a frontend"]

  # Deployment (from ArgoCD/cluster)
  annotation "deployment/images",
             description: "Deployed container images",
             title: "Container Images",
             sidebar: false,
             filter: :list
  annotation "deployment/chart",
             description: "Deployed Helm chart name",
             title: "Helm Chart",
             sidebar: false,
             filter: :word
  annotation "deployment/namespace",
             description: "Kubernetes namespace",
             title: "Namespace",
             sidebar: false,
             filter: :word
  annotation "deployment/cluster",
             description: "Target cluster name",
             title: "Cluster",
             filter: :word

  # Computed Annotations
  computed_annotation "repository/artifacts/total",
                      title: "Total Git Repositories",
                      description: "Number of related git repositories",
                      type: Integer do
    count(outgoing_transitive('TechnologyArtifact: artifact/type == "repo"'))
  end

  computed_annotation "repository/artifacts/active",
                      title: "Active Git Repositories",
                      description: "Number of related git repositories",
                      type: Integer do
    count(outgoing_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "active"'))
  end

  computed_annotation "repository/artifacts/abandoned",
                      title: "Abandoned Git Repositories",
                      description: "Number of related git repositories",
                      type: Integer do
    count(outgoing_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "abandoned"'))
  end

  computed_annotation "repository/artifacts/highBusFactor",
                      title: "High Bus Factor Repositories",
                      description: "Number of active git repositories with high bus factor",
                      type: Integer do
    count(outgoing_transitive('TechnologyArtifact: artifact/type == "repo" & activity/status == "active" & activity/busFactor == "high"'))
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

  computed_annotation "scc/language",
                      title: "Primary Language",
                      list: true,
                      description: "Programming language with most lines of code across related artifacts",
                      filter: :word,
                      sidebar: true do
    # Aggregate LOC per language across all related artifacts
    artifacts = outgoing_transitive(:TechnologyArtifact)
    loc_by_language = Hash.new(0)

    artifacts.each do |artifact|
      artifact.annotations.each do |key, value|
        # Match annotations like scc/language/Java/loc
        if key =~ %r{^scc/language/(.+)/loc$}
          language = ::Regexp.last_match(1)
          loc_by_language[language] += value.to_i
        end
      end
    end

    # Return the language with the most LOC
    loc_by_language.max_by { |_, loc| loc }&.first
  end

  computed_annotation "activity/commits",
                      title: "Monthly Commits",
                      description: "Accumulated monthly commit counts across all related repositories (excluding community repos)",
                      sidebar: false do
    artifacts = outgoing_transitive('TechnologyArtifact: artifact/type == "repo"')
    next nil if artifacts.empty?

    # Collect all commit arrays (they all end at the current month)
    # Skip community repos - their commit data reflects upstream project activity, not IONOS work
    commit_arrays = artifacts.map do |artifact|
      next nil if artifact.annotations["repository/visibility"] == "open-source"

      commits_str = artifact.annotations["activity/commits"]
      next nil if commits_str.nil? || commits_str.empty?

      commits_str.split(",").map(&:to_i)
    end.compact

    next nil if commit_arrays.empty?

    # Find the maximum length (oldest repo determines the timeline)
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
                      description: "Earliest repository creation date across all related repositories (excluding community repos)",
                      type: Time do
    artifacts = outgoing_transitive('TechnologyArtifact: artifact/type == "repo"')
    next nil if artifacts.empty?

    # Skip community repos - their creation dates reflect upstream project history, not IONOS work
    dates = artifacts.map do |artifact|
      next nil if artifact.annotations["repository/visibility"] == "open-source"

      date_str = artifact.annotations["activity/createdAt"]
      next nil if date_str.nil? || date_str.empty?

      begin
        Time.parse(date_str)
      rescue StandardError
        nil
      end
    end.compact

    dates.min
  end

  computed_annotation "activity/contributors",
                      title: "Monthly Contributors",
                      description: "Accumulated monthly unique contributor counts across all related repositories (excluding community repos)",
                      sidebar: false do
    artifacts = outgoing_transitive('TechnologyArtifact: artifact/type == "repo"')
    next nil if artifacts.empty?

    # Collect all contributor arrays (they all end at the current month)
    # Skip community repos - their contributor data reflects upstream project, not IONOS team size
    contrib_arrays = artifacts.map do |artifact|
      next nil if artifact.annotations["repository/visibility"] == "open-source"

      contrib_str = artifact.annotations["activity/contributors"]
      next nil if contrib_str.nil? || contrib_str.empty?

      contrib_str.split(",").map(&:to_i)
    end.compact

    next nil if contrib_arrays.empty?

    # Find the maximum length (oldest repo determines the timeline)
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
                      description: "Sum of unique contributors in the last 6 months across related repositories",
                      type: Integer do
    artifacts = outgoing_transitive('TechnologyArtifact: artifact/type == "repo"')
    next nil if artifacts.empty?

    # Sum unique contributor counts from related artifacts (excluding open-source repos)
    total = artifacts.sum do |artifact|
      next 0 if artifact.annotations["repository/visibility"] == "open-source"

      artifact.annotations["activity/contributors/6m"].to_i
    end
    total.positive? ? total : nil
  end

  computed_annotation "activity/contributors/total",
                      title: "Contributors (total)",
                      description: "Sum of unique contributors across related repositories",
                      type: Integer do
    artifacts = outgoing_transitive('TechnologyArtifact: artifact/type == "repo"')
    next nil if artifacts.empty?

    # Sum unique contributor counts from related artifacts (excluding open-source repos)
    total = artifacts.sum do |artifact|
      next 0 if artifact.annotations["repository/visibility"] == "open-source"

      artifact.annotations["activity/contributors/total"].to_i
    end
    total.positive? ? total : nil
  end

  relation :realizedThrough, :technologyArtifacts, :TechnologyArtifact
  relation :realizedBy, :technologyComponents, :TechnologyNode
  relation :servedBy, :technologyComponents, :TechnologySystemSoftware
  relation :exposes, :applicationInterfaces, :ApplicationInterface
  relation :dependsOn, :applicationInterfaces, :ApplicationInterface
end
