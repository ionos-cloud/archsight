# frozen_string_literal: true

require_relative "diagram/errors"
require_relative "diagram/style/theme"
require_relative "diagram/parser/lexer"
require_relative "diagram/parser"
require_relative "diagram/parser/ast"
require_relative "diagram/graph"
require_relative "diagram/layout"
require_relative "diagram/routing/edge_router"
require_relative "diagram/renderer"

module Archsight
  module Diagram
    # Parses `source` (Archsight::Diagram DSL) and renders it to an SVG document string.
    # `relation_filter` selects which edge relations to draw (layout always
    # considers all edges, since a hidden relation still represents real
    # structural coupling); defaults to dependency-first
    # (Relations::DEFAULT_FILTER).
    # `profile`, if given a Hash, is filled in with the wall-clock duration
    # (in seconds) of each pipeline stage under :parse, :graph, :layout, :render.
    # `theme` (a `Theme` name) overrides the source's own `theme "..."`
    # statement; with neither, the default theme is used.
    # `style` controls the generated `<style>` block (see `Renderer#render`):
    # `nil` (default) embeds it, `"none"` omits it entirely, anything else is
    # treated as a URL to link instead.
    # `legend` (one of `Legend::MODES`) overrides the source's own
    # `legend "..."` statement; with neither, it's placed automatically.
    def self.render(source, relation_filter: Relations::DEFAULT_FILTER, profile: nil, style: nil, theme: nil, legend: nil)
      statements = time(profile, :parse) { Parser.parse(source) }
      graph = time(profile, :graph) { Graph.build(statements) }
      resolved_theme = Theme.fetch(theme || graph.theme_name || Theme::DEFAULT.name)
      layout = time(profile, :layout) { Layout.compute(graph, theme: resolved_theme, legend: legend, relation_filter: relation_filter) }
      time(profile, :render) { Renderer.render(graph, layout, relation_filter: relation_filter, style: style) }
    end

    def self.time(profile, key)
      return yield unless profile

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      profile[key] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      result
    end
    private_class_method :time
  end
end
