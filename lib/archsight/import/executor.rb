# frozen_string_literal: true

require "archsight/import"
require_relative "registry"
require_relative "handler"
require_relative "progress"
require_relative "concurrent_progress"
require_relative "shared_file_writer"

# Executes imports in dependency order with concurrent processing
#
# The executor:
# 1. Loads all Import resources from the database
# 2. Finds pending imports whose dependencies are satisfied
# 3. Executes ready imports concurrently (up to max_concurrent)
# 4. Reloads database once after batch completes to discover new imports
# 5. Repeats until no pending imports remain
# 6. Stops immediately on first error
class Archsight::Import::Executor
  MAX_CONCURRENT = 20

  # Duration parsing patterns for cache time
  DURATION_PATTERNS = {
    /^(\d+)s$/ => 1,
    /^(\d+)m$/ => 60,
    /^(\d+)h$/ => 3600,
    /^(\d+)d$/ => 86_400
  }.freeze

  attr_reader :database, :resources_dir, :verbose

  # @param database [Archsight::Database] Database instance
  # @param resources_dir [String] Root resources directory
  # @param verbose [Boolean] Whether to print verbose debug output
  # @param max_concurrent [Integer] Maximum concurrent imports (default: 20)
  def initialize(database:, resources_dir:, verbose: false, max_concurrent: MAX_CONCURRENT)
    @database = database
    @resources_dir = resources_dir
    @verbose = verbose
    @max_concurrent = max_concurrent
    @executed_this_run = Set.new
    @iteration = 0
    @mutex = Mutex.new
  end

  # Run all pending imports
  # @raise [DeadlockError] if pending imports have unsatisfied dependencies
  # @raise [ImportError] if an import fails
  def run!
    @total_executed = 0
    @total_cached = 0
    @failed_imports = {}
    @first_error = nil
    @interrupted = false
    @concurrent_progress = Archsight::Import::ConcurrentProgress.new(max_slots: @max_concurrent)
    @shared_writer = Archsight::Import::SharedFileWriter.new

    # Calculate total imports for overall progress
    reload_database_quietly!
    total = count_all_enabled_imports
    @concurrent_progress.total = total if total.positive?

    # Track if we need to reload (skip first iteration since we just reloaded)
    need_reload = false

    loop do
      break if @interrupted

      @iteration += 1
      log "=== Iteration #{@iteration} ==="

      # Only reload if previous batch executed imports (might have generated new Import resources)
      reload_database_quietly! if need_reload

      # Get all pending imports
      pending = pending_imports

      if pending.empty?
        log "No pending imports. Done."
        break
      end

      log "Found #{pending.size} pending import(s)"

      # Find imports whose dependencies are satisfied
      ready = pending.select { |imp| dependencies_satisfied?(imp) }

      if ready.empty?
        unsatisfied = pending.map(&:name).join(", ")
        raise Archsight::Import::DeadlockError, "Deadlock: pending imports have unsatisfied dependencies: #{unsatisfied}"
      end

      # Sort by priority (lower first), then by name for determinism
      ready.sort_by! { |imp| [imp.annotations["import/priority"].to_i, imp.name] }

      # Execute all ready imports at the same priority level concurrently
      current_priority = ready.first.annotations["import/priority"].to_i
      batch = ready.select { |imp| imp.annotations["import/priority"].to_i == current_priority }

      executed_before = @total_executed
      execute_batch_concurrently(batch)

      # Close shared files before potential database reload so new content is visible
      @shared_writer.close_all

      # Only reload next iteration if imports were actually executed (not just cached)
      need_reload = @total_executed > executed_before

      # Stop on first error
      raise Archsight::Import::ImportError, "Import #{@first_error[:name]} failed: #{@first_error[:message]}" if @first_error
    end

    @shared_writer.close_all
    finish_message = build_finish_message
    @concurrent_progress.finish(finish_message) if @total_executed.positive? || @total_cached.positive?
  end

  def build_finish_message
    parts = []
    parts << "#{@total_executed} executed" if @total_executed.positive?
    parts << "#{@total_cached} cached" if @total_cached.positive?
    "Completed: #{parts.join(", ")}"
  end

  # Show execution plan without running imports
  # @return [Array<Archsight::Resources::Import>] Imports in execution order
  def execution_plan
    reload_database_quietly!

    # Collect all imports
    all_imports = database.instances_by_kind("Import")&.values || []

    # Topological sort
    sorted = topological_sort(all_imports)

    sorted.each_with_index do |imp, idx|
      enabled = imp.annotations["import/enabled"] != "false"
      deps = import_dependency_names(imp)
      deps_str = deps.empty? ? "(no dependencies)" : "depends on: #{deps.join(", ")}"
      enabled_str = enabled ? "" : " [DISABLED]"
      puts "  #{idx + 1}. #{imp.name}#{enabled_str} #{deps_str}"
    end

    sorted
  end

  private

  # Count all enabled imports (for overall progress display)
  def count_all_enabled_imports
    imports = database.instances_by_kind("Import")&.values || []
    imports.count { |imp| imp.annotations["import/enabled"] != "false" }
  end

  # Get all pending imports (enabled=true, not yet executed this run)
  def pending_imports
    imports = database.instances_by_kind("Import")&.values || []

    @mutex.synchronize do
      imports.select do |imp|
        enabled = imp.annotations["import/enabled"] != "false"
        enabled && !@executed_this_run.include?(imp.name)
      end
    end
  end

  # Check if all dependencies of an import are satisfied (executed successfully this run)
  def dependencies_satisfied?(import)
    deps = import.relations(:dependsOn, :imports)
    return true if deps.nil? || deps.empty?

    @mutex.synchronize do
      deps.all? do |dep|
        @executed_this_run.include?(dep.name) && !@failed_imports.key?(dep.name)
      end
    end
  end

  # Get dependency names for an import (for display)
  def import_dependency_names(import)
    deps = import.relations(:dependsOn, :imports)
    return [] if deps.nil? || deps.empty?

    deps.map(&:name)
  end

  # Reload database without verbose output
  def reload_database_quietly!
    original_verbose = database.verbose
    database.verbose = false
    database.reload!
  ensure
    database.verbose = original_verbose
  end

  # Execute a batch of imports concurrently
  def execute_batch_concurrently(batch)
    threads = []

    batch.each do |import|
      # Mark as executed (thread-safe)
      @mutex.synchronize { @executed_this_run.add(import.name) }

      threads << Thread.new(import) do |imp|
        # Acquire a slot (blocks if all slots are in use)
        slot_progress = @concurrent_progress.acquire_slot(imp.name)

        begin
          result = execute_single_import(imp, slot_progress)
          if result == :cached
            slot_progress.complete("Cached")
          else
            @mutex.synchronize { @total_executed += 1 }
            slot_progress.complete("Done")
          end
        rescue StandardError => e
          @mutex.synchronize do
            @failed_imports[imp.name] = e.message
            @first_error ||= { name: imp.name, message: e.message }
          end
          slot_progress.error(e.message)
        ensure
          # Update overall progress and release slot
          @concurrent_progress.increment_completed
          slot_progress.release
        end
      end
    end

    # Wait for all threads to complete, handling interrupts gracefully
    threads.each(&:join)
  rescue Interrupt
    @interrupted = true
    @concurrent_progress.finish("Interrupted")
    @shared_writer.close_all
    # Wait briefly for threads to finish current work
    threads.each { |t| t.join(0.5) }
    raise
  end

  # Execute a single import (called from thread)
  # @return [Symbol] :executed, :cached, or raises on error
  def execute_single_import(import, import_progress)
    # Check if import is still fresh based on generated/at and import/cacheTime
    if import_fresh?(import)
      @mutex.synchronize { @total_cached += 1 }
      return :cached
    end

    # Execute the import
    handler_class = Archsight::Import::Registry.handler_for(import)
    handler = handler_class.new(
      import,
      database: database,
      resources_dir: resources_dir,
      progress: import_progress,
      shared_writer: @shared_writer
    )
    handler.execute
    :executed
  end

  # Check if import is still fresh (cached)
  # Uses generated/at annotation and import/cacheTime to determine freshness
  def import_fresh?(import)
    cache_time = import.annotations["import/cacheTime"]
    return false if cache_time.nil? || cache_time.empty? || cache_time == "never"

    generated_at = import.annotations["generated/at"]
    return false if generated_at.nil? || generated_at.empty?

    ttl_seconds = parse_duration(cache_time)
    return false unless ttl_seconds

    last_run = Time.parse(generated_at)
    Time.now < (last_run + ttl_seconds)
  rescue ArgumentError
    # Invalid time format
    false
  end

  def parse_duration(str)
    return nil if str.nil?

    DURATION_PATTERNS.each do |pattern, multiplier|
      match = str.match(pattern)
      return match[1].to_i * multiplier if match
    end

    nil
  end

  # Check if an import failed during this run
  def failed?(import)
    @mutex.synchronize { @failed_imports&.key?(import.name) }
  end

  # Topological sort of imports by dependencies
  def topological_sort(imports)
    sorted = []
    visited = Set.new
    temp_visited = Set.new

    imports_by_name = imports.to_h { |imp| [imp.name, imp] }

    visit = lambda do |import|
      return if visited.include?(import.name)

      raise Archsight::Import::DeadlockError, "Circular dependency detected involving: #{import.name}" if temp_visited.include?(import.name)

      temp_visited.add(import.name)

      # Visit dependencies first
      deps = import.relations(:dependsOn, :imports)
      deps&.each do |dep|
        visit.call(dep) if imports_by_name[dep.name]
      end

      temp_visited.delete(import.name)
      visited.add(import.name)
      sorted << import
    end

    imports.each { |imp| visit.call(imp) }
    sorted
  end

  def log(msg)
    # Suppress verbose output in TTY mode as it would disrupt slot-based progress display
    return if @concurrent_progress&.tty?

    puts msg if verbose
  end
end

# Error raised when imports have circular or unsatisfied dependencies
class Archsight::Import::DeadlockError < StandardError; end

# Error raised when an import fails
class Archsight::Import::ImportError < StandardError; end
