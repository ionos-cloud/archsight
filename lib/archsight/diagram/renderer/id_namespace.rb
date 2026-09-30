# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # Prefixes every id a rendered document defines or references, so
      # several diagrams can share one HTML page without their markers,
      # gradients, filters and `asd-node-<name>` ids colliding (a duplicate
      # id makes `url(#...)` and the `#id:hover` rules resolve to whichever
      # diagram came first).
      #
      # Done on the finished markup rather than at each place an id is
      # built, because ids are built in a dozen collaborators (`ElementIds`,
      # `MarkerDefs`, `ContainerEffects`, `Legend::Row`, ...) and every one
      # of them starts `asd-` or `arrow-`. Only tag attributes and `<style>`
      # bodies are rewritten -- never text content, so a label that happens
      # to read `#asd-node-web` stays as typed. The class rules in the
      # stylesheet are identical for every diagram, so they need no scoping.
      module IdNamespace
        PREFIX_FORMAT = /\A[A-Za-z][A-Za-z0-9_-]*\z/
        ID = /(?:asd|arrow)-[\w-]*/
        TAG_REFERENCE = /(\bid="|\bdata-asd-owner="|url\(#)(#{ID})/
        STYLE_REFERENCE = /#(#{ID})/

        module_function

        def apply(svg, prefix)
          raise ArgumentError, "invalid id prefix: #{prefix.inspect}" unless PREFIX_FORMAT.match?(prefix)

          svg.gsub(%r{<style>.*?</style>|<[^<>]*>}m) do |markup|
            if markup.start_with?("<style>")
              markup.gsub(STYLE_REFERENCE) { "##{prefix}-#{Regexp.last_match(1)}" }
            else
              markup.gsub(TAG_REFERENCE) { "#{Regexp.last_match(1)}#{prefix}-#{Regexp.last_match(2)}" }
            end
          end
        end
      end
    end
  end
end
