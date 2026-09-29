# frozen_string_literal: true

require_relative "parser/lexer"
require_relative "parser/ast"
require_relative "errors"
require_relative "parser/token_cursor"
require_relative "parser/attr_parsing"
require_relative "parser/dataflow_parser"
require_relative "parser/table_layout"

module Archsight
  module Diagram
    # Recursive-descent parser over the Lexer's token stream.
    #
    # Grammar (informal):
    #   program    := statement*
    #   statement  := block | dataflow | edge | setting
    #   setting    := ("theme" | "legend" | "ranks") STRING [";"]   -- top level only
    #   block      := (CONTAINER_KEYWORD | LEAF_KEYWORD) [STRING] "{" (attr | block | edge)* "}"
    #                 -- the id is required except for ANONYMOUS_KEYWORDS
    #   dataflow   := "dataflow" STRING "{" (hop | hop_group | attr)* "}"
    #                 -- needs >= 2 hops (per branch, if a hop_group is present);
    #                    at most one hop_group per dataflow
    #   hop        := "hop" STRING [";"]
    #   hop_group  := "hop" "group" "{" (hop | branch)* "}"  -- needs >= 2 branches
    #   branch     := "branch" "{" (hop | attr)* "}"  -- needs >= 1 hop
    #   attr       := IDENT STRING [";"] | bare_flag
    #   bare_flag  := "no-gap" | "no-extend"
    #                 -- `columns "N"` on a container regroups its child
    #                    blocks into a table (see `TableLayout`)
    #   edge       := IDENT ("->" | "<->" | "--") IDENT ["{" attr* "}"]
    #
    # The `dataflow`/`hop_group`/`branch` rules live in `DataflowParser`;
    # `attr`/`bare_flag` (shared by both) live in `AttrParsing`; the raw
    # token-stream cursor lives in `TokenCursor`. This class is the
    # block/edge grammar's own top level, plus `statement`'s dispatch
    # between all three.
    class Parser
      include AttrParsing
      include TableLayout

      CONTAINER_KEYWORDS = %w[group layer stack boundary].freeze
      LEAF_KEYWORDS = %w[component application api database queue actor file].freeze
      BLOCK_KEYWORDS = (CONTAINER_KEYWORDS + LEAF_KEYWORDS).freeze
      # `layer`/`stack` may be used without an id, purely as a layout hint
      # (see AST::Block#anonymous) — a `group`/`boundary` always renders a
      # visible box, so an unnamed one wouldn't make sense the same way.
      ANONYMOUS_KEYWORDS = %w[layer stack].freeze
      SETTING_KEYWORDS = %w[theme legend ranks].freeze
      EDGE_ARROWS = {
        arrow: :directed,
        biarrow: :bidirectional,
        undirected: :undirected
      }.freeze

      attr_reader :cursor

      def self.parse(source)
        new(source).parse
      end

      def initialize(source)
        @cursor = TokenCursor.new(Lexer.new(source).tokenize)
        @anon_counter = 0
      end

      def parse
        statements = []
        statements << statement until cursor.check(:eof)
        statements
      end

      private

      def statement
        if check_block_keyword?
          block
        elsif cursor.check(:ident, "dataflow") && cursor.peek_type(1) == :string
          DataflowParser.new(cursor).parse
        elsif cursor.check(:ident) && EDGE_ARROWS.key?(cursor.peek_type(1))
          edge
        elsif SETTING_KEYWORDS.any? { |k| cursor.check(:ident, k) } && cursor.peek_type(1) == :string
          setting
        else
          t = cursor.current
          raise ParseError, "expected #{BLOCK_KEYWORDS.map(&:inspect).join(", ")}, 'dataflow', or an edge " \
                            "declaration at line #{t.line}, got #{t.type} #{t.value.inspect}#{token_hint(t)}"
        end
      end

      def block
        kind_token = cursor.advance
        kind = kind_token.value.to_sym

        id_token = cursor.check(:string) ? cursor.advance : nil
        if id_token.nil? && !ANONYMOUS_KEYWORDS.include?(kind_token.value)
          raise ParseError, "'#{kind_token.value}' at line #{kind_token.line} requires a quoted id " \
                            "(only #{ANONYMOUS_KEYWORDS.map(&:inspect).join(" and ")} can be unnamed)"
        end

        anonymous = id_token.nil?
        id = anonymous ? next_anonymous_id : id_token.value
        label = block_label(kind_token, id, anonymous)

        cursor.expect(:lbrace, "expected '{' to open #{label}")

        attrs = {}
        children = []

        parse_attrs_until_rbrace(attrs, label, expected: "an attribute, a nested block, an edge") do
          if check_block_keyword?
            children << block
            true
          elsif cursor.check(:ident) && EDGE_ARROWS.key?(cursor.peek_type(1))
            children << edge
            true
          else
            false
          end
        end

        cursor.expect(:rbrace, "expected '}' to close #{label}")

        if LEAF_KEYWORDS.include?(kind_token.value) && !children.empty?
          raise ParseError, "#{label} at line #{kind_token.line} cannot " \
                            "contain nested blocks or edges (did you mean 'group'?)"
        end

        raise ParseError, "#{label} at line #{kind_token.line}: columns only applies to containers" if LEAF_KEYWORDS.include?(kind_token.value) && attrs.key?("columns")

        children = expand_columns(attrs, children, label, kind_token.line)

        AST::Block.new(kind: kind, id: id, anonymous: anonymous, attrs: attrs, children: children, line: kind_token.line)
      end

      # `theme "compact"`, `legend "right"` -- `theme -> x` is still an edge
      # (an arrow, not a string, follows the id), so a node may still be
      # named "theme" or "legend".
      def setting
        key_token = cursor.advance
        value_token = cursor.advance
        cursor.consume(:semi)
        AST::Setting.new(key: key_token.value, value: value_token.value, line: key_token.line)
      end

      def next_anonymous_id
        @anon_counter += 1
        "__asd_anon_#{@anon_counter}"
      end

      # What a human should see identifying this block in an error message
      # -- its own id when it has one, or (since an anonymous layer/stack's
      # id is a synthetic, internal-only placeholder -- see
      # `next_anonymous_id` -- never meant to be shown) its kind plus the
      # line its own opening keyword is on, e.g. `layer (opened at line 12)`.
      def block_label(kind_token, id, anonymous)
        anonymous ? "#{kind_token.value} (opened at line #{kind_token.line})" : "#{kind_token.value} #{id.inspect}"
      end

      def edge
        from_token = cursor.advance
        arrow_token = cursor.advance
        direction = EDGE_ARROWS.fetch(arrow_token.type) do
          raise ParseError, "expected '->', '<->', or '--' after #{from_token.value.inspect} " \
                            "(line #{arrow_token.line}, got #{arrow_token.type} #{arrow_token.value.inspect})"
        end
        to_token = cursor.expect(:ident, "expected a target id after #{arrow_token.value.inspect}")

        attrs = {}
        if cursor.check(:lbrace)
          cursor.advance
          until cursor.check(:rbrace)
            line = cursor.current.line
            key, value = attr
            store_attr(attrs, key, value, line, "edge #{from_token.value} #{arrow_token.value} #{to_token.value}")
          end
          cursor.expect(:rbrace, "expected '}' to close edge attributes")
        end
        cursor.consume(:semi)

        AST::Edge.new(from: from_token.value, to: to_token.value, attrs: attrs, direction: direction, line: from_token.line)
      end

      # A block keyword is only actually a block declaration when it's
      # followed by a quoted id (`api "x" { ... }`) or directly by `{`
      # (`stack { ... }`). Without that lookahead, a node legitimately
      # named e.g. "api" would be misparsed as a new block when referenced
      # bare in an edge (`api -> db`), since block keywords and edge
      # endpoint ids share the same :ident token type — `{` never follows a
      # bare edge endpoint, so allowing it here doesn't reopen that
      # ambiguity. `{` is accepted for every keyword, not just
      # ANONYMOUS_KEYWORDS, so a keyword that isn't allowed to be anonymous
      # (e.g. `component { ... }`) still reaches `block`'s own check and
      # gets a clear "requires a quoted id" error, instead of falling
      # through to the generic "expected a block or edge" one.
      def check_block_keyword?
        cursor.check(:ident) && BLOCK_KEYWORDS.include?(cursor.current.value) &&
          %i[string lbrace].include?(cursor.peek_type(1))
      end
    end
  end
end
