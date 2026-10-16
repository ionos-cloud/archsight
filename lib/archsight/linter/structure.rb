# frozen_string_literal: true

module Archsight
  class Linter
    # Structural checks over the declared relations, the rules of "Choosing the Kind" and "Choosing the Kind:
    # Infrastructure" in the modeling guide. All findings are warnings: they point at modeling decisions to review and
    # have legitimate exceptions (internal services, capabilities that no product carries yet).
    class Structure
      # Network types that run over another network and need one that serves them
      OVERLAY_TYPES = %w[overlay vpn].freeze
      NETWORK_DEVICE_TYPES = %w[switch router].freeze

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
          equipment_without_facility,
          device_without_facility,
          device_connected_to_itself,
          network_device_realizing_no_network,
          device_served_apart_from_its_equipment
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

      # A device that is part of equipment (a rack) or of another device (a virtual chassis) is placed through its
      # whole, and a chassis through its members
      def device_without_facility
        parts = owners_by_target("TechnologyDevice", :composedOf, :technologyDevices)
        racked = owners_by_target("TechnologyEquipment", :composedOf, :technologyDevices)
        instances("TechnologyDevice").filter_map do |device|
          next if parts.key?(device) || racked.key?(device) || targets(device, :composedOf, :technologyDevices).any?
          next if targets(device, :locatedAt, :technologyFacilities).any?

          warning(device, "is located at no TechnologyFacility")
        end
      end

      def device_connected_to_itself
        instances("TechnologyDevice").filter_map do |device|
          next unless targets(device, :connectedTo, :technologyDevices).include?(device)

          warning(device, "is connectedTo itself")
        end
      end

      # The members of a virtual chassis or stack realize the network through the chassis
      def network_device_realizing_no_network
        realized = owners_by_target("TechnologyCommunicationNetwork", :realizedBy, :technologyDevices)
        members = owners_by_target("TechnologyDevice", :composedOf, :technologyDevices)
        instances("TechnologyDevice").filter_map do |device|
          type = device.annotations["device/type"]
          next unless NETWORK_DEVICE_TYPES.include?(type)
          next if realized.key?(device) || members.key?(device)

          warning(device, "is a #{type} that realizes no TechnologyCommunicationNetwork")
        end
      end

      # A device in a partition (equipment servedBy a team) serves that team; one that names another team has been
      # handed over without moving it. A device that names no team is served through its equipment.
      def device_served_apart_from_its_equipment
        holders = owners_by_target("TechnologyEquipment", :composedOf, :technologyDevices)
        instances("TechnologyDevice").filter_map do |device|
          teams = targets(device, :servedBy, :businessActors)
          equipment_teams = holders.fetch(device, []).flat_map { |equipment| targets(equipment, :servedBy, :businessActors) }
          next if teams.empty? || equipment_teams.empty?

          others = teams - equipment_teams
          next if others.empty?

          warning(device, "is servedBy #{names(others.sort_by(&:name))}, not by the team of its equipment " \
                          "(#{names(equipment_teams.uniq.sort_by(&:name))})")
        end
      end
    end
  end
end
