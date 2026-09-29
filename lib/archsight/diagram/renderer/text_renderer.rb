# frozen_string_literal: true

require_relative "../support/text_metrics"

module Archsight
  module Diagram
    class Renderer
      # Halo'd `<text>`/markdown-lite rendering. Owns the deferred `@texts`
      # accumulator -- every label in the diagram (node labels, container
      # titles, edge labels, the legend) is collected here instead of being
      # interleaved into the SVG body, and emitted last by `Renderer#render`
      # so it always paints on top of everything else (SVG has no z-index;
      # paint order is document order).
      class TextRenderer
        include SvgFormat

        TEXT_COLOR = "#1a202c"
        # The CSS class `Renderer::Stylesheet` defines for `TEXT_COLOR`,
        # applied to a `<text>` with no more specific `fill_class:` of its
        # own (see `halo_text`'s default) -- the single source of truth for
        # both is `TEXT_COLOR` itself, so they can never drift apart.
        DEFAULT_FILL_CLASS = "asd-text"
        # How far apart stacked lines of a multi-line label sit, in px.
        LABEL_LINE_HEIGHT_EM = 1.3

        attr_reader :texts

        def initialize
          @texts = []
        end

        # -- a solid white stroke drawn *behind* the fill
        # (`paint-order="stroke"` strokes first, fills on top) so text stays
        # legible against whatever's directly behind it. Rather than
        # returning the markup for the caller to embed at the call site
        # (which would only draw it on top of whatever was already drawn
        # *before* it -- e.g. a node label would still sit under an edge
        # line added later), it's appended to `@texts` and drawn last, on
        # top of the whole diagram; callers that do `body.raw(halo_text(...))`
        # get "" back, a harmless no-op.
        # `link:` wraps the whole rendered text in an `<a>` (a node-level
        # `link` attribute making its entire label one click target); `text`
        # itself may also carry its own inline `[label](url)` markdown-lite
        # link(s), which get their own, narrower `<a>` around just that run
        # -- except when `link:` is already wrapping everything, since SVG
        # (like HTML) can't nest an `<a>` inside another `<a>`.
        # `attrs:` are extra attributes for the `<text>` itself -- its `id`
        # and `data-asd-*` source attributes (see `ElementIds#label_attrs`).
        def halo_text(x, y, text, font_size:, fill_class: DEFAULT_FILL_CLASS, weight: nil, anchor: "middle", baseline: nil,
                      link: nil, defer: true, attrs: {}, extra_class: nil)
          classes = ["asd-text-halo", "asd-fs-#{font_size}", "asd-text-anchor-#{anchor}", fill_class]
          classes << extra_class if extra_class
          classes << "asd-text-bold" if weight == "bold"
          classes << "asd-text-baseline-#{baseline}" if baseline
          # A node-level link's own affordance (cursor/hover) lives entirely
          # on the wrapping <a>, which a static export (PNG, or any SVG
          # viewer without interactivity) never shows -- an explicit
          # underline on the text itself is what stays visible there too.
          classes << "asd-underline" if link
          content = text_content_markup(text, x: x, font_size: font_size, suppress_inline_links: !link.nil?)

          m = Markup.new
          m.element_with_content("text", content, id: attrs[:id], x: fmt(x), y: fmt(y), class: classes, **attrs.except(:id))
          markup = wrap_link(m.to_s, link)

          # Deferring (the default) is what guarantees every label paints on
          # top of content added *after* it -- not needed for a legend row's
          # own label, which nothing else paints over once the legend itself
          # is drawn, and where the caller instead wants the markup right
          # here so it can wrap it in the same <g> as the row's icon (see
          # `Renderer::LegendRenderer#render`).
          return markup unless defer

          @texts << markup
          ""
        end

        def label_text(x, y, text, font_size: 13, link: nil, attrs: {}, extra_class: nil)
          halo_text(x, y, text, font_size: font_size, baseline: "central", link: link, attrs: attrs, extra_class: extra_class)
        end

        # Wraps already-built `markup` in a clickable `<a>` when `link` is
        # present, otherwise returns it untouched.
        def wrap_link(markup, link)
          return markup unless link

          m = Markup.new
          m.element("a", href: link, class: "asd-link") { m.raw(markup) }
          m.to_s
        end

        private

        # The inner markup for a (possibly multi-line, possibly
        # markdown-lite-formatted) label. A single line with no markdown --
        # still the overwhelming common case -- returns exactly the same
        # flat, escaped string `halo_text` always has, so nothing about that
        # case's rendered output changes.
        def text_content_markup(text, x:, font_size:, suppress_inline_links: false)
          lines = TextMetrics.lines(text)

          return line_markup(lines.first, suppress_inline_links: suppress_inline_links) if lines.length == 1

          line_height = font_size * LABEL_LINE_HEIGHT_EM
          first_dy = -(lines.length - 1) * line_height / 2.0

          lines.each_with_index.map do |line, i|
            dy = i.zero? ? first_dy : line_height
            Markup.tag("tspan", line_markup(line, suppress_inline_links: suppress_inline_links), x: fmt(x), dy: fmt(dy))
          end.join
        end

        def line_markup(line, suppress_inline_links: false)
          TextMetrics.markdown_runs(line).map { |content, style| run_markup(content, style, suppress_inline_links: suppress_inline_links) }.join
        end

        # A plain run (no formatting) stays bare escaped text, so a label
        # with no markdown at all never grows any `<tspan>` wrapping.
        def run_markup(content, style, suppress_inline_links: false)
          return escape(content) if style.empty?

          classes = []
          classes << "asd-run-bold" if style[:bold]
          classes << "asd-run-italic" if style[:italic]
          classes << "asd-run-underline" if style[:underline] || style[:link]

          span = Markup.tag("tspan", escape(content), class: classes)
          return span if style[:link].nil? || suppress_inline_links

          Markup.tag("a", span, href: style[:link], class: "asd-link")
        end
      end
    end
  end
end
