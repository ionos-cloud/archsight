# frozen_string_literal: true

module Archsight
  # Resources contains all resources to reflect the architecture assets
  module Resources
    # Store the class mapping
    @resource_classes = {}

    # Kinds that were renamed: the old name is still accepted (see Database#create_valid_instance) and reported
    # as deprecated by `archsight lint`. The table is only consulted by lookups; `each` and `resource_classes`
    # list every kind once, under its new name. Remove an entry (and its relation keys below) to end the transition.
    KIND_ALIASES = {
      "BusinessRequirement" => "MotivationRequirement",
      "BusinessConstraint" => "MotivationConstraint"
    }.freeze

    # Relation keys (the plural kind names under `spec.<verb>`) that were renamed together with their kind
    RELATION_KEY_ALIASES = {
      "businessRequirements" => "motivationRequirements",
      "businessConstraints" => "motivationConstraints"
    }.freeze

    # Relations that are never written in a file: they are derived from what a resource's text and diagram say
    # (see Archsight::References). `mentions` comes from links in text, `depicts` from the nodes of a diagram.
    # Every kind can have them towards every kind, so instead of one relation per target kind a class gets one per
    # verb, under the key DERIVED_KEY, that holds resources of any kind (relations are followed by looking at the
    # resources they hold, not at the kind they were declared for).
    DERIVED_VERBS = %i[mentions depicts].freeze
    DERIVED_KEY = :resources

    # The derived relations of every class, next to the ones it declares: [verb, key, kind]
    DERIVED_RELATIONS = DERIVED_VERBS.map { |verb| [verb, DERIVED_KEY, "Resource"] }.freeze

    # The current name of a kind, whichever of its names is given
    def self.canonical(klass_name)
      name = klass_name.to_s
      KIND_ALIASES.fetch(name, name)
    end

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

    # Returns the class by name; a renamed kind is found under its old name too
    def self.[](klass_name)
      @resource_classes[canonical(klass_name)]
    end

    # Iterate over all resource class names (sorted)
    def self.each(&)
      @resource_classes.keys.sort.each(&)
    end

    # Get the constant by name (for backward compatibility with const_get)
    def self.const_get(name)
      @resource_classes[canonical(name)] || super
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
