# frozen_string_literal: true

module Archsight
  # Resources contains all resources to reflect the architecture assets
  module Resources
    # Store the class mapping
    @resource_classes = {}

    # Register a resource class
    def self.register(klass)
      # Skip anonymous classes (used in tests)
      return if klass.name.nil?

      name = klass.name.split("::").last
      @resource_classes[name] = klass
    end

    # Returns all registered resource classes
    def self.resource_classes
      @resource_classes
    end

    # Returns the class by name
    def self.[](klass_name)
      @resource_classes[klass_name.to_s]
    end

    # Iterate over all resource class names (sorted)
    def self.each(&)
      @resource_classes.keys.sort.each(&)
    end

    # Get the constant by name (for backward compatibility with const_get)
    def self.const_get(name)
      @resource_classes[name.to_s] || super
    end
  end
end

# Load dependencies after module is defined
require_relative "helpers"

# Define the Annotations namespace before loading annotation files
# (required for compact class definitions like Archsight::Annotations::Annotation)
module Archsight::Annotations; end

Dir[File.join(__dir__, "annotations", "*.rb")].each { |file| require_relative file }
require_relative "resources/base"
Dir[File.join(__dir__, "resources", "*.rb")].each { |file| require_relative file }
