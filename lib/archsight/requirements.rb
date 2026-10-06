# frozen_string_literal: true

module Archsight
  # The business requirements of a selection of resources, as the "Business Requirements" table of an instance page
  # shows them, merged over all resources of the selection: one entry per BusinessRequirement, with the status the
  # resources give it (`realizes` = implemented, `partiallyRealizes` = partial, `plans` = planned).
  #
  #   Requirements.collect(db, of: 'ApplicationService: name =~ "Backup"', priority: ["must"])
  #   # => [{ name: "Requirement:X", status: "partial", priority: "must", story: "...",
  #   #       by: [{ kind: "ApplicationService", name: "Backup", status: "partial" }] }]
  module Requirements
    # Relation verb -> status, best first
    STATUSES = { "realizes" => "implemented", "partiallyRealizes" => "partial", "plans" => "planned" }.freeze
    PRIORITIES = %w[must should may].freeze
    RELATION = :businessRequirements

    module_function

    # @param of [String] query selecting the resources whose requirements are listed
    # @param priority [Array<String>] only these priorities (empty: all)
    # @param status [Array<String>] only requirements with one of these statuses (empty: all)
    # @return [Array<Hash>] sorted by priority (must, should, may, none), then name
    # @raise [Archsight::Query::QueryError] if `of` is not a valid query
    def collect(database, of:, priority: [], status: [])
      found = {}
      Archsight::Query.parse(of).filter(database).each do |resource|
        STATUSES.each do |verb, resource_status|
          resource.relations(verb, RELATION).each do |requirement|
            entry = (found[requirement.name] ||= { requirement: requirement, by: [] })
            entry[:by] << { kind: resource.class.name.split("::").last, name: resource.name, status: resource_status }
          end
        end
      end

      entries = found.values.map { |entry| entry(entry[:requirement], entry[:by]) }
      entries = entries.select { |e| priority.include?(e[:priority]) } unless priority.empty?
      entries = entries.select { |e| status.include?(e[:status]) } unless status.empty?
      entries.sort_by { |e| [PRIORITIES.index(e[:priority]) || PRIORITIES.size, e[:name]] }
    end

    def entry(requirement, by)
      by = by.sort_by { |b| [STATUSES.values.index(b[:status]), b[:kind], b[:name]] }
      {
        name: requirement.name,
        status: by.first[:status],
        priority: requirement.annotations["requirement/priority"],
        story: requirement.annotations["requirement/story"],
        by: by
      }
    end
  end
end
