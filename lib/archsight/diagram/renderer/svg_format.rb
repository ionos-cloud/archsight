# frozen_string_literal: true

module Archsight
  module Diagram
    # Number/text formatting shared by every markup-building collaborator --
    # not renderer-specific (Representers needs the exact same number
    # formatting), so this lives at the top level rather than under Renderer.
    module SvgFormat
      module_function

      def fmt(number)
        format("%.2f", number)
      end

      def escape(text)
        text.to_s
            .gsub("&", "&amp;")
            .gsub("<", "&lt;")
            .gsub(">", "&gt;")
            .gsub('"', "&quot;")
      end
    end
  end
end
