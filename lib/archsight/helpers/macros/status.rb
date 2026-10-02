# frozen_string_literal: true

require "erb"
require "digest"
require_relative "../../diagram"

module Archsight
  module Helpers
    module Macros
      # `{status:yellow WIP}`: a small coloured lozenge, like the status macro of Confluence. It is shown as an
      # SVG that the status endpoint generates (`GET /api/v1/status/yellow/WIP.svg`).
      module Status
        # background, text and border, in the colours of the Confluence lozenges (text contrast >= 4.5:1)
        COLOURS = {
          "grey" => %w[#dfe1e6 #42526e #c1c7d0],
          "red" => %w[#ffebe6 #bf2600 #ffbdad],
          "yellow" => %w[#fff0b3 #7a5200 #ffe380],
          "green" => %w[#e3fcef #006644 #abf5d1],
          "blue" => %w[#deebff #0747a6 #b3d4ff],
          "purple" => %w[#eae6ff #403294 #c0b6f2]
        }.freeze
        MAX_TEXT = 40
        HEIGHT = 20
        FONT_SIZE = 11
        PADDING = 7
        MIN_WIDTH = 75 # a lozenge of a short word ("OK") should not shrink to a speck
        CACHE_SIZE = 500
        ROOT = "/api/v1/status"

        Value = Struct.new(:colour, :text)

        @cache = {}
        @lock = Mutex.new

        class << self
          # @return [Value, nil] nil unless the arguments are a known colour and a text of 1..40 characters
          def parse(arguments)
            colour, text = arguments.to_s.strip.split(/\s+/, 2)
            return unless colour && text && COLOURS.key?(colour.downcase)

            text = text.strip
            Value.new(colour.downcase, text) if valid_text?(text)
          end

          def valid_text?(text) = text.length.between?(1, MAX_TEXT) && !text.match?(/[{}\p{Cc}]/)

          def problem(arguments, _context = nil)
            return if parse(arguments)

            "expected a colour (#{COLOURS.keys.join(", ")}) and a text of 1 to #{MAX_TEXT} characters without braces"
          end

          def html(value, _context = nil)
            %(<img class="macro-status" src="#{h(url(value.colour, value.text))}" alt="#{h(value.text)}" loading="lazy" />)
          end

          def confluence(value, _context = nil)
            %(<ac:structured-macro ac:name="status"><ac:parameter ac:name="colour">#{value.colour.capitalize}</ac:parameter>) +
              %(<ac:parameter ac:name="title">#{h(value.text)}</ac:parameter></ac:structured-macro>)
          end

          # The path of the generated SVG; the text is percent-encoded so it survives markdown and HTML
          def url(colour, text) = "#{ROOT}/#{colour}/#{ERB::Util.url_encode(text)}.svg"

          # The SVG of a lozenge, cached (the colour and the text fully determine it)
          # @return [String, nil] nil for an unknown colour or an invalid text
          def svg(colour, text)
            colour = colour.to_s.downcase
            return unless COLOURS.key?(colour) && valid_text?(text.to_s.strip)

            key = [colour, text.strip]
            @lock.synchronize do
              @cache.shift if @cache.length >= CACHE_SIZE && !@cache.key?(key)
              @cache[key] ||= draw(colour, text.strip)
            end
          end

          def etag(svg) = %("#{Digest::SHA256.hexdigest(svg)[0, 16]}")

          private

          def draw(colour, text)
            background, ink, border = COLOURS.fetch(colour)
            label = text.upcase
            width = lozenge_width(label)
            <<~SVG.delete("\n")
              <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{HEIGHT}" viewBox="0 0 #{width} #{HEIGHT}" role="img" aria-label="#{h(text)}">
              <title>#{h(text)}</title>
              <rect x=".5" y=".5" width="#{width - 1}" height="#{HEIGHT - 1}" rx="3" fill="#{background}" stroke="#{border}"/>
              <text x="#{width / 2.0}" y="14" text-anchor="middle" font-family="Helvetica,Arial,sans-serif" font-size="#{FONT_SIZE}" font-weight="700" letter-spacing=".2" fill="#{ink}">#{h(label)}</text>
              </svg>
            SVG
          end

          # Bold Helvetica widths of the label (as the diagrams measure), letter spacing and the padding
          def lozenge_width(label)
            table = Diagram::TextMetrics::HELVETICA_BOLD_WIDTHS
            units = label.each_char.sum { |c| table.fetch(c.ord - 32, Diagram::TextMetrics::FALLBACK_WIDTH) }
            [((units * FONT_SIZE / 1000.0) + (label.length * 0.2) + (2 * PADDING)).ceil, MIN_WIDTH].max
          end

          def h(text) = ERB::Util.html_escape(text)
        end
      end

      register("status", Status)
    end
  end
end
