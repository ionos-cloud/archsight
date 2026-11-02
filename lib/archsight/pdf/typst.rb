# frozen_string_literal: true

module Archsight
  module Pdf
    # Building blocks for Typst source (https://typst.app). All text is emitted as Typst string literals
    # (`#"..."`) and structure as function calls (`#strong[...]`), so no content can be mistaken for markup.
    module Typst
      LANGUAGE = /\A[A-Za-z0-9+#-]+\z/

      module_function

      # A Typst string literal, for use as a function argument
      def lit(text)
        escaped = text.to_s.delete("\r").gsub(/[\\"]/) { "\\#{Regexp.last_match(0)}" }.gsub("\n", "\\n")
        "\"#{escaped}\""
      end

      # A Typst string literal as markup, for use inside content
      def str(text)
        "##{lit(text)}"
      end

      # A block of preformatted text
      def raw(source, lang = nil)
        lang_arg = lang.to_s.match?(LANGUAGE) ? ", lang: #{lit(lang)}" : ""
        "#raw(#{lit(source.to_s.chomp)}, block: true#{lang_arg})"
      end

      # A short text on a coloured background (a status)
      def badge(text, hex)
        "#box(fill: #{color(hex)}, inset: (x: 4pt, y: 1pt), radius: 2pt)[#{str(text)}]"
      end

      # A framed message that stands where something could not be shown
      def note(text, fill: "#fff3cc")
        "#block(fill: #{color(fill)}, inset: 8pt, radius: 3pt, width: 100%)[#{str(text)}]"
      end

      # A Typst colour from `#rrggbb` / `#rgb`
      def color(hex)
        "rgb(#{lit(hex)})"
      end
    end
  end
end
