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

    # The requirements of a ```requirements block as a plain table (see ViewTable), for places that cannot run the frontend.
    # "Realized by" is only there when more than one resource contributes.
    # @param spec [Hash] the parsed block: `{ title:, of:, priority:, status: }` (Helpers::RequirementsBlocks.parse)
    # @raise [Archsight::Query::QueryError]
    def table(database, spec)
      entries = collect(database, of: spec[:of], priority: spec[:priority], status: spec[:status])
      with_by = entries.flat_map { |e| e[:by].map { |b| [b[:kind], b[:name]] } }.uniq.length > 1
      cell = ViewTable::Cell
      rows = entries.first(ViewTable::LIMIT).map do |e|
        row = [cell.new(text: e[:status], as: :status), cell.new(text: e[:name]), cell.new(text: e[:priority].to_s, as: :priority),
               cell.new(text: e[:story].to_s, as: :markdown)]
        row << cell.new(text: e[:by].map { |b| b[:name] }.join("\n")) if with_by
        row
      end
      ViewTable::Table.new(title: spec[:title].to_s.empty? ? "Business Requirements" : spec[:title],
                           columns: ["Status", "Name", "Priority", "Story", ("Realized by" if with_by)].compact, rows: rows, total: entries.length)
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
