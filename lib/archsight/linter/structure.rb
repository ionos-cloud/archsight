# frozen_string_literal: true

module Archsight
  class Linter
    # Structural checks over the declared relations, the rules of "Choosing the Kind" and "Choosing the Kind:
    # Infrastructure" in the modeling guide. All findings are warnings: they point at modeling decisions to review and
    # have legitimate exceptions (internal services, capabilities that no product carries yet).
    class Structure
      # Network types that run over another network and need one that serves them
      OVERLAY_TYPES = %w[overlay vpn].freeze

      def initialize(database)
        @database = database
      end

      # Findings in a stable order, each starting with the path reference of the resource
      def warnings
        [
          component_in_several_services,
          artifact_in_several_components,
          service_with_same_named_component,
          product_without_service,
          service_reached_from_nothing,
          capability_without_product,
          generated_component_in_several_repositories,
          link_not_between_two_facilities,
          overlay_without_underlay,
          facility_without_location,
          equipment_without_facility
        ].flatten.sort
      end

      private

      def instances(kind)
        @database.instances_by_kind(kind).values
      end

      def targets(instance, verb, key)
        instance.relations(verb, key)
      end

      def warning(instance, message)
        "#{instance.path_ref}: #{instance.klass} '#{instance.name}' #{message}"
      end

      def names(list)
        list.map { |item| "'#{item.name}'" }.join(", ")
      end

      # { target => [owners that list it under verb/key] } for the instances of `kind`
      def owners_by_target(kind, verb, key)
        owners = Hash.new { |hash, target| hash[target] = [] }
        instances(kind).each { |owner| targets(owner, verb, key).each { |target| owners[target] << owner } }
        owners
      end

      def component_in_several_services
        shared("ApplicationService", :realizedThrough, :applicationComponents, "services")
      end

      def artifact_in_several_components
        shared("ApplicationComponent", :realizedThrough, :technologyArtifacts, "components")
      end

      def shared(kind, verb, key, plural)
        owners_by_target(kind, verb, key).filter_map do |target, owners|
          next if owners.length < 2

          warning(target, "is realized by #{owners.length} #{plural}: #{names(owners.sort_by(&:name))}")
        end
      end

      def service_with_same_named_component
        instances("ApplicationService").filter_map do |service|
          components = targets(service, :realizedThrough, :applicationComponents)
          next unless components.length == 1 && components.first.name == service.name

          warning(service, "has one component with the same name")
        end
      end

      def product_without_service
        instances("BusinessProduct").filter_map do |product|
          next unless targets(product, :servedBy, :applicationServices).empty?

          warning(product, "is served by no ApplicationService")
        end
      end

      # A service is reached when a product or process is served by it, directly or through services that depend on it
      def service_reached_from_nothing
        reached = reached_services
        instances("ApplicationService").filter_map do |service|
          next if reached.include?(service)

          warning(service, "is not served to any product or process")
        end
      end

      def reached_services
        reached = []
        queue = (instances("BusinessProduct") + instances("BusinessProcess")).flat_map { |item| targets(item, :servedBy, :applicationServices) }
        until queue.empty?
          service = queue.shift
          next if reached.include?(service)

          reached << service
          queue.concat(targets(service, :dependsOn, :applicationServices))
        end
        reached
      end

      def capability_without_product
        realized = owners_by_target("BusinessProduct", :realizes, :strategyCapabilities)
        instances("StrategyCapability").filter_map do |capability|
          next if realized.key?(capability)

          warning(capability, "is realized by no product")
        end
      end

      # A generated component realized by several repositories is two components merged into one: the repositories
      # declare the same module path. A re-import gives each its own name (GoModuleParser#owned_component_name).
      def generated_component_in_several_repositories
        instances("ApplicationComponent").filter_map do |component|
          next unless component.annotations.key?("generated/script")

          repositories = targets(component, :realizedThrough, :technologyArtifacts).select { |a| a.name.start_with?("Repo:") }
          next if repositories.length < 2

          warning(component, "is generated from #{repositories.length} repositories with the same module path: " \
                             "#{names(repositories.sort_by(&:name))}")
        end
      end

      # ---- infrastructure

      def link_not_between_two_facilities
        instances("TechnologyEquipment").filter_map do |equipment|
          next unless equipment.annotations["equipment/type"] == "link"

          count = targets(equipment, :locatedAt, :technologyFacilities).length
          next if count == 2

          warning(equipment, "is a link located at #{count} #{count == 1 ? "facility" : "facilities"}, not 2")
        end
      end

      def overlay_without_underlay
        instances("TechnologyCommunicationNetwork").filter_map do |network|
          type = network.annotations["network/type"]
          next unless OVERLAY_TYPES.include?(type)
          next unless targets(network, :servedBy, :technologyCommunicationNetworks).empty?

          warning(network, "is #{type == "overlay" ? "an" : "a"} #{type} network served by no network")
        end
      end

      # Only the outermost facility needs a location; nested halls inherit it from their campus
      def facility_without_location
        nested = owners_by_target("TechnologyFacility", :composedOf, :technologyFacilities)
        instances("TechnologyFacility").filter_map do |facility|
          next if nested.key?(facility) || targets(facility, :locatedAt, :locations).any?

          warning(facility, "is located at no Location")
        end
      end

      # TechnologyEquipment that is part of other equipment is placed through its whole, and a whole (a backbone) through its
      # parts (the links)
      def equipment_without_facility
        parts = owners_by_target("TechnologyEquipment", :composedOf, :technologyEquipment)
        instances("TechnologyEquipment").filter_map do |equipment|
          next if parts.key?(equipment) || targets(equipment, :composedOf, :technologyEquipment).any?
          next if targets(equipment, :locatedAt, :technologyFacilities).any?

          warning(equipment, "is located at no TechnologyFacility")
        end
      end
    end
  end
end
