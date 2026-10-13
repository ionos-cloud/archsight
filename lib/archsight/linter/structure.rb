# frozen_string_literal: true

module Archsight
  class Linter
    # Structural checks over the declared relations, the rules of "Choosing the Kind" in the modeling guide. All
    # findings are warnings: they point at modeling decisions to review and have legitimate exceptions (internal
    # services, capabilities that no product carries yet).
    class Structure
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
          capability_without_product
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
    end
  end
end
