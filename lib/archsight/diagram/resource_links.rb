# frozen_string_literal: true

module Archsight
  module Diagram
    # Turns `resource "Archsight:Web"` node attributes into links, using a
    # resolver the caller supplies -- the diagram renderer itself knows
    # nothing about the resource database.
    #
    # `resolver.call(reference)` returns the link's URL, `nil` for a resource
    # that exists but has nowhere to link to (the node stays as it is), or
    # `:missing` / `:ambiguous`. A resolved node gets a plain `link` (so it
    # renders like any other linked node); an unresolved one is marked `broken`
    # instead of failing the whole diagram, and reported to `unresolved` when given.
    # Without a resolver (the standalone `archsight diagram`) a `resource`
    # attribute is valid but inert.
    module ResourceLinks
      REASONS = { missing: "not found", ambiguous: "is ambiguous, use Kind/Name" }.freeze

      module_function

      def apply(graph, resolver, unresolved = nil)
        return unless resolver

        graph.nodes_by_id.each_value do |node|
          reference = node.attrs["resource"]
          next unless reference

          outcome = resolver.call(reference)
          next if outcome.nil?

          if outcome.is_a?(String)
            node.attrs["link"] = outcome
          else
            reason = REASONS.fetch(outcome) { raise ArgumentError, "resolver returned #{outcome.inspect} for #{reference.inspect}" }
            node.attrs["broken"] = "Resource #{reference} #{reason}"
            unresolved&.push({ node: node.id, reference: reference, reason: reason, line: node.line })
          end
        end
      end
    end
  end
end
