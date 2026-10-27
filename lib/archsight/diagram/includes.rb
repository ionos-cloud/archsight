# frozen_string_literal: true

module Archsight
  module Diagram
    # Expands `include "<path>"` statements: each one is replaced, at its position, by the statements of the
    # diagram it names. The renderer knows nothing about where diagrams live; the caller supplies a loader
    # (`archsight://` and `file://` paths, see `Helpers::DiagramIncludes`).
    #
    # `loader.call(path)` returns the source of the included diagram, or `:missing` / `:forbidden` / `:invalid`.
    # Included sources may include others. An include inside a container takes blocks and edges only: a
    # `dataflow` or a `theme`/`legend`/`ranks` setting belongs to the whole diagram, so it is left out there
    # and reported in `Result#warnings`.
    # Edges need no such care, they are resolved by id once the whole graph is built, so a fragment may link to
    # nodes of the diagram that includes it and the other way round.
    class Includes
      MAX_DEPTH = 8
      MAX_INCLUDES = 100
      REASONS = { missing: "not found", forbidden: "is not allowed", invalid: "is not a valid include path" }.freeze

      # The expanded statements, the sources that were loaded (`{ path => source }`, in order) and what was
      # left out of them (warning messages).
      Result = Struct.new(:statements, :sources, :warnings, keyword_init: true)

      # @param statements [Array] parsed statements of the main source
      # @param loader [#call, nil]
      # @raise [IncludeError]
      def self.expand(statements, loader)
        new(loader).expand(statements)
      end

      def self.includes?(statements)
        statements.any? { |s| s.is_a?(AST::Include) || (s.is_a?(AST::Block) && includes?(s.children)) }
      end

      def initialize(loader)
        @loader = loader
        @sources = {}
        @warnings = []
        @count = 0
      end

      def expand(statements)
        Result.new(statements: splice(statements, [], top: true), sources: @sources, warnings: @warnings)
      end

      private

      def splice(statements, stack, top:)
        statements.flat_map do |stmt|
          case stmt
          when AST::Include then included(stmt, stack, top: top)
          when AST::Block
            stmt.children = splice(stmt.children, stack, top: false)
            [stmt]
          else [stmt]
          end
        end
      end

      def included(stmt, stack, top:)
        path = stmt.path
        raise IncludeError, "include cycle: #{(stack + [path]).join(" -> ")} (line #{stmt.line})" if stack.include?(path)
        raise IncludeError, "include #{path.inspect} (line #{stmt.line}) is nested deeper than #{MAX_DEPTH} levels" if stack.length >= MAX_DEPTH

        @count += 1
        raise IncludeError, "too many includes (more than #{MAX_INCLUDES})" if @count > MAX_INCLUDES

        source = load(path, stmt.line)
        @sources[path] = source
        parsed = parse(path, source)
        parsed = drop_whole_diagram_statements(path, parsed, stmt.line) unless top
        splice(parsed, stack + [path], top: top)
      end

      def load(path, line)
        raise IncludeError, "include #{path.inspect} (line #{line}) is not available here" unless @loader

        result = @loader.call(path)
        return result if result.is_a?(String)

        reason = REASONS.fetch(result) { raise ArgumentError, "include loader returned #{result.inspect} for #{path.inspect}" }
        raise IncludeError, "include #{path.inspect} #{reason} (line #{line})"
      end

      def parse(path, source)
        Parser.parse(source, anon_scope: "i#{@count}_")
      rescue ParseError, GraphError => e
        raise IncludeError, "in include #{path.inspect}: #{e.message}"
      end

      # Dataflows and settings apply to the whole diagram, so inside a container they are ignored (with a warning)
      def drop_whole_diagram_statements(path, parsed, line)
        dropped, kept = parsed.partition { |s| s.is_a?(AST::DataFlow) || s.is_a?(AST::Setting) }
        dropped.each do |s|
          what = s.is_a?(AST::DataFlow) ? "dataflow #{s.id.inspect}" : "#{s.key} setting"
          @warnings << "include #{path.inspect} (line #{line}): the #{what} (line #{s.line}) is ignored, it only applies when included at the top level"
        end
        kept
      end
    end
  end
end
