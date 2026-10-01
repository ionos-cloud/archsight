# frozen_string_literal: true

module Archsight
  # Exporters publish wiki pages to other systems (`archsight export --to <target>`).
  module Export
    class Error < StandardError; end

    TARGETS = %w[confluence].freeze

    module_function

    # @param target [String] one of TARGETS
    # @return [Class] the exporter class, which is built with `new(database:, resources_dir:, **options)` and answers `run(names)`
    def exporter_for(target)
      case target
      when "confluence"
        require_relative "export/confluence/exporter"
        Confluence::Exporter
      else
        raise Error, "unknown export target #{target.inspect} (expected one of: #{TARGETS.join(", ")})"
      end
    end
  end
end
