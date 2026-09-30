# frozen_string_literal: true

require "strscan"
require_relative "../errors"
require_relative "../support/markdown_text"

module Archsight
  module Diagram
    # Turns DSL source text into a flat token stream.
    #
    # Token types: :ident, :string, :arrow, :biarrow, :undirected, :lbrace,
    # :rbrace, :semi, :eof
    #
    # Built on `StringScanner` so the per-character work happens inside the
    # regex engine rather than a Ruby-level loop (~6x faster), and so the
    # position is a byte offset -- indexing a non-ASCII string by char is
    # O(n) per lookup, which would make a char-by-char lexer quadratic.
    class Lexer
      Token = Struct.new(:type, :value, :line, keyword_init: true)

      # `-` is an identifier char, but never a leading one: a token starting
      # with `-` is always an arrow (`->`/`--`), see `read_dash`.
      IDENTIFIER = %r{[A-Za-z0-9_./-]+}
      # Same character set `\s` matches, minus `\n` (counted separately).
      WHITESPACE = /[ \t\r\f\v]+/
      COMMENT = /#[^\n]*/
      NEWLINES = /\n+/
      PUNCTUATION = { "{" => :lbrace, "}" => :rbrace, ";" => :semi }.freeze

      # Inside a string literal: a run of plain chars, one escape, or the
      # indentation at the start of a continuation line.
      STRING_CHUNK = /[^"\\\n]+/
      STRING_ESCAPE = /\\(.)/m
      CONTINUATION_INDENT = /[ \t]+/

      def initialize(source)
        @scanner = StringScanner.new(source)
        @line = 1
      end

      def tokenize
        tokens = []
        loop do
          token = next_token
          tokens << token
          break if token.type == :eof
        end
        tokens
      end

      private

      def next_token
        skip_whitespace_and_comments

        return Token.new(type: :eof, value: nil, line: @line) if @scanner.eos?

        char = @scanner.peek(1)
        case char
        when '"'
          read_string
        when "{", "}", ";"
          @scanner.getch
          Token.new(type: PUNCTUATION.fetch(char), value: char, line: @line)
        when "-"
          read_dash
        when "<"
          read_biarrow
        else
          value = @scanner.scan(IDENTIFIER)
          raise ParseError, "unexpected character #{@scanner.check(/./m).inspect} at line #{@line}" unless value

          Token.new(type: :ident, value: value, line: @line)
        end
      end

      # A string can carry a real multi-line label two ways: an explicit
      # `\n` escape (kept exactly as typed, no trimming -- it's on one
      # physical source line, so there's no source indentation to strip,
      # and a space right after it is presumably intentional), or the
      # string literal itself spanning several physical lines in the
      # `.asd` source, where each continuation line's leading indentation
      # (an artifact of how the source file happens to be formatted, not
      # content) is stripped, along with each line's trailing whitespace.
      # A plain single-line string never touches any of this.
      def read_string
        start_line = @line
        @scanner.getch # opening quote
        value = +""
        at_line_start = false
        loop do
          if @scanner.skip(/"/)
            break
          elsif at_line_start && @scanner.skip(CONTINUATION_INDENT)
            # skip a continuation line's own leading indentation
          elsif (chunk = @scanner.scan(STRING_CHUNK))
            value << chunk
            at_line_start = false
          elsif @scanner.skip(/\n/)
            value = value.rstrip
            value << "\n"
            @line += 1
            at_line_start = true
          elsif @scanner.scan(STRING_ESCAPE)
            value << (@scanner[1] == "n" ? "\n" : @scanner[1])
            @line += 1 if @scanner[1] == "\n" # an escaped newline is still a line break in the source
            at_line_start = false
          else
            # end of input, or a lone trailing backslash right before it
            raise ParseError, "unterminated string starting at line #{start_line}"
          end
        end

        value = value.rstrip if value.include?("\n")
        Token.new(type: :string, value: MarkdownText.detect(value), line: start_line)
      end

      def read_dash
        if @scanner.skip(/->/)
          Token.new(type: :arrow, value: "->", line: @line)
        elsif @scanner.skip(/--/)
          Token.new(type: :undirected, value: "--", line: @line)
        else
          raise ParseError, "unexpected character '-' at line #{@line} (did you mean '->' or '--'?)"
        end
      end

      def read_biarrow
        raise ParseError, "unexpected character '<' at line #{@line} (did you mean '<->'?)" unless @scanner.skip(/<->/)

        Token.new(type: :biarrow, value: "<->", line: @line)
      end

      def skip_whitespace_and_comments
        loop do
          if (newlines = @scanner.skip(NEWLINES))
            @line += newlines
          elsif !@scanner.skip(WHITESPACE) && !@scanner.skip(COMMENT)
            return
          end
        end
      end
    end
  end
end
