# frozen_string_literal: true

module Archsight
  module Diagram
    class Renderer
      # A small SVG-building helper: tracks nesting depth so every line's
      # leading whitespace is correct by construction, however deep an
      # element ends up nested, and accepts `class:` as a plain Ruby Array
      # (strings and/or symbols, `nil`s dropped).
      #
      # Attribute keys are passed exactly as the SVG attribute needs to read
      # (`x:`, `"stroke-dasharray":`, `viewBox:`) -- no underscore/hyphen
      # guessing, since SVG mixes kebab-case and camelCase attributes and a
      # wrong guess would silently produce bad markup. Coordinate values are
      # passed through `SvgFormat.fmt` explicitly by the caller -- this
      # class doesn't try to auto-detect "coordinate" vs. "small
      # fixed constant" (a marker's `markerWidth="7"` needs to stay `"7"`,
      # not become `"7.00"`).
      class Markup
        INDENT = "  "

        def initialize
          @out = +""
          @depth = 0
        end

        def to_s = @out

        # A self-closing element (`<tag ... />`) when no block is given, or
        # an opening/closing pair wrapping whatever the block appends (at
        # one deeper indent level) when one is.
        def element(tag, **attrs)
          line "<#{tag}#{self.class.attrs_string(attrs)}#{" /" unless block_given?}>"
          return unless block_given?

          @depth += 1
          yield
          @depth -= 1
          line "</#{tag}>"
        end

        # A single-line "<tag attrs>content</tag>" -- `content` is used
        # verbatim (already escaped, and/or already-built inner markup, e.g.
        # a label's mix of escaped text and nested `<tspan>`s -- see
        # `TextRenderer`) rather than treated as a nested block, since it
        # belongs on the same line as its own opening/closing tag.
        def element_with_content(tag, content, **attrs)
          line "<#{tag}#{self.class.attrs_string(attrs)}>#{content}</#{tag}>"
        end

        # Appends externally-built markup -- or raw CSS text inside
        # `<style>`, never XML-escaped -- at the current depth, one line at
        # a time. The escape hatch for content this class doesn't itself
        # construct (a `Representers::*#markup`/`TextRenderer#halo_text`
        # result, already built via this same class starting from its own
        # fresh depth-0 instance).
        def raw(markup)
          markup.each_line { |l| @out << "#{INDENT * @depth}#{l}" }
        end

        # A flat, single-line tag with no depth/newline of its own -- for
        # content that's inline *within* another element's single line (a
        # `<tspan>` inside a `<text>`, an `<a>` inside a `<tspan>`) rather
        # than a document-level element in its own right.
        def self.tag(name, content = nil, **attrs)
          content ? "<#{name}#{attrs_string(attrs)}>#{content}</#{name}>" : "<#{name}#{attrs_string(attrs)} />"
        end

        # Every value is XML-escaped (`class` after joining) -- safe even for
        # the overwhelming majority of values that need no escaping (numbers,
        # path `d` strings, internal ids), and correct for the ones that
        # sometimes do (a `link` attr's URL, an id/label taken from user
        # source), without any call site needing to remember to escape.
        def self.attrs_string(attrs)
          attrs.filter_map do |key, value|
            next if value.nil?

            formatted = key == :class ? Array(value).flatten.compact.join(" ") : value
            %( #{key}="#{SvgFormat.escape(formatted)}")
          end.join
        end

        private

        def line(text) = @out << "#{INDENT * @depth}#{text}\n"
      end
    end
  end
end
