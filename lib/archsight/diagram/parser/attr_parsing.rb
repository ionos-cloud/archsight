# frozen_string_literal: true

module Archsight
  module Diagram
    class Parser
      # `attr`/bare-flag parsing, shared by `Parser` (a block's own attrs)
      # and `DataflowParser` (a dataflow/branch's own attrs) -- both parse
      # the exact same `IDENT STRING [";"] | bare_flag` grammar rule, just
      # inside a different enclosing block. Every including class must
      # define its own `cursor` (a `TokenCursor`).
      module AttrParsing
        # Terser, preferred alternative to writing out `gap "0"`/`extend
        # "false"` explicitly -- a bare ident with no following value.
        BARE_FLAGS = {
          "no-gap" => %w[gap 0],
          "no-extend" => %w[extend false]
        }.freeze

        def attr
          key_token = cursor.advance
          value_token = cursor.expect(:string, "expected a quoted value for attribute '#{key_token.value}'")
          cursor.consume(:semi)
          [key_token.value, value_token.value]
        end

        # Only a bare-flag ident with no following string counts -- `no-gap
        # "x"` (unusual, but not disallowed) falls through to the generic
        # `attr` case instead, treating "no-gap" as a literal (inert
        # downstream) attr key rather than the flag.
        def bare_flag?
          cursor.check(:ident) && BARE_FLAGS.key?(cursor.current.value) && cursor.peek_type(1) != :string
        end

        def bare_flag
          token = cursor.advance
          cursor.consume(:semi)
          BARE_FLAGS.fetch(token.value)
        end

        # Reads attr/bare-flag pairs into `attrs` until `}`, first giving
        # the caller's own block a chance to handle anything else a
        # particular context also allows there (a nested block/edge for
        # `Parser#block`, a `hop`/`hop group` for `DataflowParser#parse`,
        # a `hop` for `DataflowParser#branch`) -- the block returns truthy
        # if it handled the current token, falsy to fall through to
        # attr/bare-flag. `error_context` names what's being parsed (see
        # `Parser#block_label` for why an anonymous block never shows its
        # synthetic id here); `expected` is the caller's own extra grammar
        # (whatever its yield block handles), spelled out in the fallback
        # "unexpected token" message instead of leaving the reader to guess
        # what else was valid.
        def parse_attrs_until_rbrace(attrs, error_context, expected:)
          until cursor.check(:rbrace)
            next if yield

            line = cursor.current.line
            if bare_flag?
              key, value = bare_flag
              store_attr(attrs, key, value, line, error_context)
            elsif cursor.check(:ident)
              key, value = attr
              store_attr(attrs, key, value, line, error_context)
            else
              t = cursor.current
              raise ParseError, "expected #{expected}, or '}' to close #{error_context}, but got " \
                                "#{t.type} #{t.value.inspect} at line #{t.line}#{token_hint(t)}"
            end
          end
        end

        # A second `label "..."` in one block would silently replace the
        # first (the hash keeps only the last), so it's an error instead.
        def store_attr(attrs, key, value, line, error_context)
          raise ParseError, "duplicate attribute '#{key}' in #{error_context} at line #{line}" if attrs.key?(key)

          attrs[key] = value
        end

        # A short, common-mistake-specific nudge appended to an "unexpected
        # token"/"expected ..." message -- both a stray `{` and a bare
        # quoted string usually mean the same thing (a missing block
        # keyword right before it, or, for `{`, possibly an unclosed block
        # earlier whose missing `}` shifted everything after it).
        def token_hint(t)
          case t.type
          when :lbrace
            " (a stray '{' usually means a missing keyword right before it, or an unclosed block earlier in the file)"
          when :string
            " (a bare quoted string here usually needs a keyword before it, e.g. component \"id\" { ... })"
          else
            ""
          end
        end
      end
    end
  end
end
