# frozen_string_literal: true

module Archsight
  module Diagram
    class Parser
      # Read-only-lookahead, mutate-on-advance cursor over the Lexer's
      # token stream -- the primitive every grammar rule (block/edge/
      # dataflow/hop group/branch, in both `Parser` and `DataflowParser`)
      # builds on.
      class TokenCursor
        def initialize(tokens)
          @tokens = tokens
          @pos = 0
        end

        def check(type, value = nil)
          return false if @pos >= @tokens.length

          t = current
          t.type == type && (value.nil? || t.value == value)
        end

        def peek_type(offset)
          idx = @pos + offset
          idx < @tokens.length ? @tokens[idx].type : :eof
        end

        def current
          @tokens[@pos]
        end

        def advance
          t = current
          @pos += 1 unless t.type == :eof
          t
        end

        def expect(type, message)
          return advance if check(type)

          t = current
          raise ParseError, "#{message} (line #{t.line}, got #{t.type} #{t.value.inspect})"
        end

        def consume(type)
          advance if check(type)
        end
      end
    end
  end
end
