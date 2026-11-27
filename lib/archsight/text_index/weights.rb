# frozen_string_literal: true

# How much a hit of a kind counts in the ranking of a text search: the relevance (bm25) is multiplied by it. Pages
# are what people look for first, then the application layer, technology last; settings kinds rank low. A Config of
# type `search` (the one named `default`, else the first) sets a layer with `search/weight-<layer>` and a single
# kind with `search/weight-<Kind>`. Order: configured kind, configured layer, built-in kind, built-in layer.
module Archsight
  class TextIndex
    class Weights
      TYPE = "search" # the `config/type` of the Config that holds the weights
      DEFAULT_CONFIG = "default"
      PREFIX = "search/weight-"
      MAX = 100

      LAYER_DEFAULTS = {
        "application" => 1.5,
        "business" => 1.2,
        "strategy" => 1.2,
        "motivation" => 1.2,
        "implementation" => 1.0,
        "technology" => 1.0,
        "other" => 0.5
      }.freeze

      KIND_DEFAULTS = {
        "Page" => 3.0,
        "ApplicationService" => 2.0,
        "ApplicationComponent" => 2.0,
        "ApplicationInterface" => 1.5
      }.freeze

      class << self
        # The weights of the model (built-in defaults replaced by its search Config)
        def for(database)
          new(configured(database))
        end

        # nil when the value is a valid weight, else the message (the validator of the Config annotation)
        def value_error(value)
          number = Float(value.to_s, exception: false)
          number&.between?(0, MAX) ? nil : "expected a number from 0 to #{MAX} such as 1.5"
        end

        private

        # {suffix => weight} of the search Config; values that are not valid weights are left out (the linter reports them)
        def configured(database)
          configs = database.instances_by_kind("Config").values.select { |c| c.annotations["config/type"].to_s.casecmp?(TYPE) }
          config = configs.find { |c| c.name == DEFAULT_CONFIG } || configs.first
          return {} unless config

          config.annotations.each_with_object({}) do |(key, value), weights|
            next unless key.start_with?(PREFIX) && value_error(value).nil?

            weights[key.delete_prefix(PREFIX)] = Float(value.to_s)
          end
        end
      end

      def initialize(configured = {})
        @configured = configured
        @cache = {}
      end

      # The weight of a resource class
      def [](klass)
        @cache[klass] ||= begin
          kind = klass.to_s.split("::").last
          layer = klass.respond_to?(:layer) ? klass.layer : "other"
          # as the summary lens: what the Config says beats the built-ins, the kind beats the layer
          @configured[kind] || @configured[layer] || KIND_DEFAULTS[kind] || LAYER_DEFAULTS.fetch(layer, 1.0)
        end
      end
    end
  end
end
