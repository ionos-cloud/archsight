# frozen_string_literal: true

module Archsight
  module Diagram
    class Parser
      # The `dataflow "id" { ... }` sub-grammar: `dataflow`/`hop_group`/
      # `branch`/hop-count validation -- the most intricate part of the
      # grammar, split out so `Parser` itself reads as the block/edge
      # grammar's own top level. Constructed with the same `TokenCursor`
      # `Parser` itself is walking, so the two stay perfectly interleaved
      # (a dataflow can appear anywhere a statement can).
      class DataflowParser
        include AttrParsing

        attr_reader :cursor

        def initialize(cursor)
          @cursor = cursor
        end

        # `hop "id"` entries repeat the same key, so they're collected into
        # an array rather than folded into the `attrs` Hash the way `attr`
        # does for everything else (`color`, `label`) in the same block. A
        # `hop` may instead introduce a `group { ... }` (at most one per
        # dataflow), collected as a single `AST::DataFlowGroup` element in
        # the same `hops` array.
        def parse
          kw_token = cursor.advance
          id_token = cursor.expect(:string, "expected a quoted id for 'dataflow'")

          cursor.expect(:lbrace, "expected '{' to open dataflow #{id_token.value.inspect}")

          hops = []
          attrs = {}
          saw_group = false

          parse_attrs_until_rbrace(attrs, "dataflow #{id_token.value.inspect}", expected: "an attribute, 'hop', 'hop group'") do
            if cursor.check(:ident, "hop") && cursor.peek_type(1) == :string
              cursor.advance
              hop_token = cursor.expect(:string, "expected a quoted node id for 'hop'")
              cursor.consume(:semi)
              hops << hop_token.value
              true
            elsif cursor.check(:ident, "hop") && cursor.peek_type(1) == :ident
              if saw_group
                t = cursor.current
                raise ParseError, "dataflow #{id_token.value.inspect} at line #{t.line} may only have one 'hop group'"
              end
              saw_group = true
              cursor.advance # the "hop" ident
              hops << hop_group(id_token)
              true
            else
              false
            end
          end

          cursor.expect(:rbrace, "expected '}' to close dataflow #{id_token.value.inspect}")

          validate_dataflow_hops(hops, id_token, kw_token)

          AST::DataFlow.new(id: id_token.value, hops: hops, attrs: attrs, line: kw_token.line)
        end

        private

        # `hop group { hop "x"; hop "y"; branch { hop "a"; hop "b"; label "..." } }`
        # -- a bare `hop STRING` is sugar for a single-hop `branch` with no
        # overrides; `branch { (hop|attr)* }` allows a multi-hop sub-chain
        # and/or a `label`/`color` override for just that branch.
        def hop_group(df_id_token)
          cursor.advance # the "group" ident
          group_kw = cursor.expect(:lbrace, "expected '{' to open 'hop group' in dataflow #{df_id_token.value.inspect}")

          branches = []
          until cursor.check(:rbrace)
            if cursor.check(:ident, "hop")
              cursor.advance
              hop_token = cursor.expect(:string, "expected a quoted node id for 'hop'")
              cursor.consume(:semi)
              branches << AST::DataFlowBranch.new(hops: [hop_token.value], attrs: {}, line: hop_token.line)
            elsif cursor.check(:ident, "branch")
              branches << branch(df_id_token)
            else
              t = cursor.current
              raise ParseError, "expected 'hop' or 'branch' inside 'hop group' of dataflow " \
                                "#{df_id_token.value.inspect}, but got #{t.type} #{t.value.inspect} " \
                                "at line #{t.line}#{token_hint(t)}"
            end
          end

          cursor.expect(:rbrace, "expected '}' to close 'hop group' in dataflow #{df_id_token.value.inspect}")

          if branches.length < 2
            raise ParseError, "'hop group' in dataflow #{df_id_token.value.inspect} at line #{group_kw.line} " \
                              "needs at least 2 branches, got #{branches.length}"
          end

          AST::DataFlowGroup.new(branches: branches, line: group_kw.line)
        end

        def branch(df_id_token)
          kw_token = cursor.advance
          cursor.expect(:lbrace, "expected '{' to open 'branch' in dataflow #{df_id_token.value.inspect}")

          hops = []
          attrs = {}
          parse_attrs_until_rbrace(attrs, "'branch' of dataflow #{df_id_token.value.inspect}", expected: "an attribute, 'hop'") do
            if cursor.check(:ident, "hop")
              cursor.advance
              hop_token = cursor.expect(:string, "expected a quoted node id for 'hop'")
              cursor.consume(:semi)
              hops << hop_token.value
              true
            else
              false
            end
          end

          cursor.expect(:rbrace, "expected '}' to close 'branch' in dataflow #{df_id_token.value.inspect}")

          if hops.empty?
            raise ParseError, "'branch' in dataflow #{df_id_token.value.inspect} at line #{kw_token.line} " \
                              "needs at least 1 hop"
          end

          AST::DataFlowBranch.new(hops: hops, attrs: attrs, line: kw_token.line)
        end

        # Without a group, the whole dataflow needs >= 2 hops, same as
        # before. With a group, that rule applies per branch: the shared
        # prefix/suffix around the group, plus that branch's own hops, must
        # still total >= 2.
        def validate_dataflow_hops(hops, id_token, kw_token)
          group_index = hops.index { |h| h.is_a?(AST::DataFlowGroup) }

          if group_index.nil?
            if hops.length < 2
              raise ParseError, "dataflow #{id_token.value.inspect} at line #{kw_token.line} needs at least 2 hops, " \
                                "got #{hops.length}"
            end
            return
          end

          prefix_len = hops[0...group_index].length
          suffix_len = hops[(group_index + 1)..].length

          hops[group_index].branches.each do |b|
            total = prefix_len + b.hops.length + suffix_len
            next if total >= 2

            raise ParseError, "dataflow #{id_token.value.inspect} at line #{kw_token.line} needs at least 2 hops " \
                              "on every branch, got #{total}"
          end
        end
      end
    end
  end
end
