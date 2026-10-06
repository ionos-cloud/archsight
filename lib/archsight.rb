# frozen_string_literal: true

require_relative "archsight/version"
require_relative "archsight/configuration"
require_relative "archsight/helpers"
require_relative "archsight/graph"
require_relative "archsight/renderer"
require_relative "archsight/database"
require_relative "archsight/linter"
require_relative "archsight/template"
require_relative "archsight/documentation"
require_relative "archsight/query"
require_relative "archsight/requirements"
require_relative "archsight/view_table"
require_relative "archsight/resources"

module Archsight
  # Loaded on first use: the DSL-to-SVG diagram renderer is only needed by `archsight diagram`
  autoload :Diagram, "archsight/diagram"
end

module Archsight
  class Error < StandardError; end
end
