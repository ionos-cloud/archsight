# frozen_string_literal: true

require "erb"

module Archsight
  module Helpers
    module Macros
      # `{emoticon:2705}` or `{emoticon:2705 check mark button}`: an emoji by its hex code point(s) (several joined
      # with `-`) and an optional name, like the emoticon macro of Confluence. Shown as the character itself.
      # `{emoticon:minus}`: one of the classic Confluence emoticons by name (see LEGACY).
      module Emoticon
        Value = Struct.new(:id, :name, :char)

        # The classic emoticons of Confluence (the ones without an emoji code point) and the emoji they stand for
        LEGACY = {
          "smile" => "\u{1F642}", "sad" => "\u{1F641}", "cheeky" => "\u{1F61B}", "laugh" => "\u{1F604}", "wink" => "\u{1F609}",
          "thumbs-up" => "\u{1F44D}", "thumbs-down" => "\u{1F44E}", "information" => "\u2139\uFE0F", "tick" => "\u2705",
          "cross" => "\u274C", "warning" => "\u26A0\uFE0F", "plus" => "\u2795", "minus" => "\u2796", "question" => "\u2753",
          "light-bulb-on" => "\u{1F4A1}", "light-bulb-off" => "\u{1F4A1}", "yellow-star" => "\u2B50", "red-star" => "\u2B50",
          "green-star" => "\u2B50", "blue-star" => "\u2B50"
        }.freeze

        # Everything the pictographic ranges and joiners of emoji sequences cover; anything else is not an emoji
        ALLOWED = /\A(?:\p{Emoji_Presentation}|\p{Extended_Pictographic}|[\u{1F3FB}-\u{1F3FF}\u{200D}\u{FE0F}\u{20E3}\u{1F1E6}-\u{1F1FF}0-9#*])+\z/

        class << self
          # @return [Value, nil] nil for anything that is not hex code points of an emoji
          def parse(arguments)
            id, name = arguments.to_s.strip.split(/\s+/, 2)
            return Value.new(nil, id, LEGACY.fetch(id)) if name.nil? && LEGACY.key?(id)
            return unless id&.match?(/\A\h{1,6}(?:-\h{1,6})*\z/)

            char = id.split("-").map { |hex| hex.to_i(16) }.pack("U*")
            return unless char.valid_encoding? && char.match?(ALLOWED)

            Value.new(id.downcase, name&.strip.then { |n| n unless n.to_s.empty? || n.match?(/[{}\p{Cc}]/) }, char)
          rescue RangeError
            nil
          end

          def problem(arguments, _context = nil)
            parse(arguments) ? nil : "expected the hex code point(s) of an emoji, for example 2705 or 1f468-200d-1f4bb, with an optional name, or a classic name (#{LEGACY.keys.join(", ")})"
          end

          def html(value, _context = nil)
            label = value.name ? %( aria-label="#{h(value.name)}" title="#{h(value.name)}") : ""
            %(<span class="macro-emoticon" role="img"#{label}>#{h(value.char)}</span>)
          end

          def confluence(value, _context = nil)
            return %(<ac:emoticon ac:name="#{h(value.name)}"/>) unless value.id

            name = value.name ? %( ac:name="#{h(value.name)}") : ""
            %(<ac:emoticon ac:emoji-id="#{value.id}"#{name} ac:emoji-fallback="#{h(value.char)}"/>)
          end

          private

          def h(text) = ERB::Util.html_escape(text)
        end
      end

      register("emoticon", Emoticon)
    end
  end
end
