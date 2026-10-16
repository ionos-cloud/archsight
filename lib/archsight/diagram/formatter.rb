# frozen_string_literal: true

require "strscan"
require_relative "errors"
require_relative "parser"

module Archsight
  module Diagram
    # Tidies `.asd` source without rewriting it: every line is indented by
    # its brace depth (`INDENT` per level, a line opening with `}` one level
    # less), trailing whitespace is dropped, runs of blank lines become one
    # and the file ends in exactly one newline. Comments, line breaks and
    # one-line blocks (`component "a" { label "x"; tint "y" }`) stay as
    # written. Works on the text, not the parse tree, because the lexer
    # drops comments.
    #
    # A string spanning several lines keeps its blank lines; its
    # continuation lines are indented one level below the line that opens
    # it (the lexer strips that indentation, so it is not content).
    #
    # `format` checks that the result parses to the same diagram as the
    # source (line numbers aside) and raises `Error` if not, so a bug here
    # can never change a diagram.
    module Formatter
      INDENT = "  "

      module_function

      # @raise [Archsight::Diagram::Error] if `source` does not parse
      def format(source)
        before = comparable(Parser.parse(source))
        formatted = reindent(source)
        raise Error, "formatting would change the diagram" unless comparable(Parser.parse(formatted)) == before

        formatted
      end

      def reindent(source)
        lines = []
        depth = 0
        in_string = false
        source.each_line(chomp: true) do |raw|
          text = raw.rstrip
          continuation = in_string
          closers, delta, in_string = scan(text, in_string)
          text = text.lstrip unless continuation && text.empty?
          level = continuation ? depth + 1 : [depth - closers, 0].max
          lines << (text.empty? ? "" : (INDENT * level) + text) << continuation
          depth = [depth + delta, 0].max
        end
        tidy(lines.each_slice(2).to_a)
      end

      # `[leading closing braces, brace depth change, still inside a string
      # at the end]` of one line, ignoring braces in strings and comments.
      def scan(text, in_string)
        scanner = StringScanner.new(text)
        delta = 0
        closers = 0
        leading = !in_string
        until scanner.eos?
          if in_string
            in_string = false if scanner.scan(/(?:[^"\\]|\\.)*"/)
            scanner.terminate if in_string
            leading = false
          elsif scanner.skip(/\s+/)
            next
          elsif scanner.skip(/#.*/)
            break
          elsif scanner.skip(/"/)
            in_string = true
            leading = false
          elsif scanner.skip(/\{/)
            delta += 1
            leading = false
          elsif scanner.skip(/\}/)
            delta -= 1
            closers += 1 if leading
          else
            scanner.skip(/[^\s"{}#]+/)
            leading = false
          end
        end
        [closers, delta, in_string]
      end

      # Joins `[line, inside a string]` pairs: one blank line at most between
      # statements (blank lines inside a string are content), none at the
      # start or end.
      def tidy(pairs)
        out = []
        pairs.each do |line, continuation|
          next if line.empty? && !continuation && (out.empty? || out.last.empty?)

          out << line
        end
        out.pop while out.last&.empty?
        out.empty? ? "" : "#{out.join("\n")}\n"
      end

      # The parse tree without line numbers, which formatting may change.
      def comparable(node)
        case node
        when Array then node.map { |child| comparable(child) }
        when Hash then node.transform_values { |value| comparable(value) }
        when Struct then [node.class, node.to_h.except(:line).transform_values { |value| comparable(value) }]
        else node
        end
      end
    end
  end
end
