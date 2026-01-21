# frozen_string_literal: true

require_relative "../annotations/relation_resolver"

module Archsight
  module Analysis
    # Sandbox provides a safe execution context for Analysis scripts.
    # Scripts are evaluated via instance_eval with access only to
    # explicitly defined methods.
    class Sandbox
      # Output sections collected during script execution
      attr_reader :sections

      def initialize(database)
        @database = database
        @sections = []
        @resolver_cache = {}
      end

      # Instance iteration methods

      # Iterate over all instances of a kind
      # @param kind [Symbol, String] Resource kind (e.g., :ApplicationService)
      # @yield [instance] Block called for each instance
      def each_instance(kind, &)
        instances(kind).each(&)
      end

      # Get all instances of a kind
      # @param kind [Symbol, String] Resource kind
      # @return [Array] Array of instances
      def instances(kind)
        @database.instances_by_kind(kind.to_s).values
      end

      # Get a specific instance by kind and name
      # @param kind [Symbol, String] Resource kind
      # @param name [String] Instance name
      # @return [Object, nil] Instance or nil if not found
      def instance(kind, name)
        @database.instance_by_kind(kind.to_s, name)
      end

      # Relation traversal methods (reuse ComputedRelationResolver)

      # Get direct outgoing relations
      # @param inst [Object] Source instance
      # @param kind [Symbol, nil] Optional kind filter
      # @return [Array] Related instances
      def outgoing(inst, kind = nil)
        resolver_for(inst).outgoing(kind)
      end

      # Get transitive outgoing relations
      # @param inst [Object] Source instance
      # @param kind [Symbol, nil] Optional kind filter
      # @param max_depth [Integer] Maximum traversal depth
      # @return [Array] Transitively related instances
      def outgoing_transitive(inst, kind = nil, max_depth: 10)
        resolver_for(inst).outgoing_transitive(kind, max_depth: max_depth)
      end

      # Get direct incoming relations (instances that reference this one)
      # @param inst [Object] Target instance
      # @param kind [Symbol, nil] Optional kind filter
      # @return [Array] Instances referencing this one
      def incoming(inst, kind = nil)
        resolver_for(inst).incoming(kind)
      end

      # Get transitive incoming relations
      # @param inst [Object] Target instance
      # @param kind [Symbol, nil] Optional kind filter
      # @param max_depth [Integer] Maximum traversal depth
      # @return [Array] Instances transitively referencing this one
      def incoming_transitive(inst, kind = nil, max_depth: 10)
        resolver_for(inst).incoming_transitive(kind, max_depth: max_depth)
      end

      # Data access methods

      # Get an annotation value from an instance
      # @param inst [Object] Instance
      # @param key [String] Annotation key
      # @return [Object, nil] Annotation value
      def annotation(inst, key)
        inst.annotations[key]
      end

      # Get all annotations from an instance (frozen copy)
      # @param inst [Object] Instance
      # @return [Hash] Frozen hash of annotations
      def annotations(inst)
        inst.annotations.dup.freeze
      end

      # Get the name of an instance
      # @param inst [Object] Instance
      # @return [String] Instance name
      def name(inst)
        inst.name
      end

      # Get the kind of an instance
      # @param inst [Object] Instance
      # @return [String] Instance kind
      def kind(inst)
        inst.klass
      end

      # Query method

      # Execute a query string
      # @param query_string [String] Query string
      # @return [Array] Matching instances
      def query(query_string)
        @database.query(query_string)
      end

      # Aggregation methods

      # Sum numeric values
      # @param values [Array<Numeric>] Values to sum
      # @return [Numeric] Sum
      def sum(values)
        values.compact.sum
      end

      # Count items
      # @param items [Array] Items to count
      # @return [Integer] Count
      def count(items)
        items.compact.count
      end

      # Calculate average
      # @param values [Array<Numeric>] Values to average
      # @return [Float, nil] Average or nil if empty
      def avg(values)
        compact = values.compact
        return nil if compact.empty?

        compact.sum.to_f / compact.size
      end

      # Find minimum value
      # @param values [Array<Numeric>] Values
      # @return [Numeric, nil] Minimum
      def min(values)
        values.compact.min
      end

      # Find maximum value
      # @param values [Array<Numeric>] Values
      # @return [Numeric, nil] Maximum
      def max(values)
        values.compact.max
      end

      # Collect values into array
      # @param items [Array] Items
      # @param key [String, Symbol, nil] Optional key to extract
      # @yield [item] Optional block to transform items
      # @return [Array] Collected values
      def collect(items, key = nil, &block)
        if block
          items.map(&block).compact
        elsif key
          items.map { |item| item.respond_to?(key) ? item.send(key) : item.annotations[key.to_s] }.compact
        else
          items.compact
        end
      end

      # Group items by a key
      # @param items [Array] Items to group
      # @yield [item] Block that returns the grouping key
      # @return [Hash] Grouped items
      def group_by(items, &)
        items.group_by(&)
      end

      # Output methods - Structured content building

      # Add a heading
      # @param text [String] Heading text
      # @param level [Integer] Heading level (0-6, default 0)
      #   Level 0 creates accordion sections in the web UI
      #   Levels 1-6 map to HTML h2-h6 within sections
      def heading(text, level: 0)
        @sections << { type: :heading, text: text, level: level.clamp(0, 6) }
      end

      # Add a text paragraph
      # @param content [String] Text content (supports markdown)
      def text(content)
        @sections << { type: :text, content: content }
      end

      # Add a table
      # @param headers [Array<String>] Column headers
      # @param rows [Array<Array>] Table rows (each row is an array of values)
      def table(headers:, rows:)
        return if rows.empty?

        @sections << { type: :table, headers: headers, rows: rows }
      end

      # Add a bullet list
      # @param items [Array<String, Hash>] List items (strings or hashes with :text key)
      def list(items)
        return if items.empty?

        @sections << { type: :list, items: items }
      end

      # Add a code block
      # @param content [String] Code content
      # @param lang [String] Language for syntax highlighting (default: plain)
      def code(content, lang: "")
        @sections << { type: :code, content: content, lang: lang }
      end

      # Legacy output methods - still supported for backward compatibility

      # Report findings (legacy method - creates appropriate section based on data type)
      # @param data [Object] Report data (usually Array or Hash)
      # @param title [String, nil] Optional report title
      def report(data, title: nil)
        heading(title, level: 1) if title

        case data
        when Array
          report_array(data)
        when Hash
          report_hash(data)
        else
          text(data.to_s)
        end
      end

      # Log a warning message
      # @param message [String] Warning message
      def warning(message)
        @sections << { type: :message, level: :warning, message: message }
      end

      # Log an error message
      # @param message [String] Error message
      def error(message)
        @sections << { type: :message, level: :error, message: message }
      end

      # Log an info message
      # @param message [String] Info message
      def info(message)
        @sections << { type: :message, level: :info, message: message }
      end

      # Configuration access

      # Get a configuration value from the analysis
      # @param key [String] Configuration key (without 'analysis/config/' prefix)
      # @return [Object, nil] Configuration value
      def config(key)
        @current_analysis&.annotations&.[]("analysis/config/#{key}")
      end

      # Set the current analysis being executed (called by Executor)
      # @param analysis [Object] Analysis instance
      # @api private
      def _set_analysis(analysis)
        @current_analysis = analysis
      end

      private

      # Get or create a relation resolver for an instance
      def resolver_for(inst)
        @resolver_cache[inst.name] ||= Archsight::Annotations::ComputedRelationResolver.new(inst, @database)
      end

      # Report an array - auto-detect if it's a table or list
      def report_array(data)
        return if data.empty?

        # If array of hashes with consistent keys, render as table
        if data.all? { |item| item.is_a?(Hash) }
          keys = data.first.keys
          if data.all? { |item| item.keys == keys }
            table(headers: keys.map(&:to_s), rows: data.map { |item| keys.map { |k| item[k] } })
            return
          end
        end

        # Otherwise render as list
        list(data.map { |item| format_list_item(item) })
      end

      # Report a hash - render as definition list or table
      def report_hash(data)
        return if data.empty?

        # Render as simple key-value list
        list(data.map { |k, v| "**#{k}:** #{v}" })
      end

      # Format a list item for display
      def format_list_item(item)
        case item
        when Hash
          item.map { |k, v| "#{k}=#{v}" }.join(", ")
        else
          item.to_s
        end
      end
    end
  end
end
