# frozen_string_literal: true

require "digest"
require "json"
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

  attr_reader :database, :resources_dir, :verbose, :filter, :force

  # @param database [Archsight::Database] Database instance
  # @param resources_dir [String] Root resources directory
  # @param verbose [Boolean] Whether to print verbose debug output
  # @param max_concurrent [Integer] Maximum concurrent imports (default: 20)
  # @param output [IO] Output stream for progress (default: $stdout)
  # @param filter [String, nil] Regex pattern to match import names
  # @param force [Boolean] Whether to bypass cache and re-run all imports
  # @param deps [Boolean] With a filter, also run the imports the matched ones depend on (false: only the matched ones)
  def initialize(database:, resources_dir:, verbose: false, max_concurrent: MAX_CONCURRENT, output: $stdout, filter: nil, force: false,
                 deps: true)
    @database = database
    @resources_dir = resources_dir
    @verbose = verbose
    @max_concurrent = max_concurrent
    @output = output
    @filter = filter
    @filter_regex = Regexp.new(filter, Regexp::IGNORECASE) if filter
    @force = force
    @deps = deps
    @executed_this_run = Set.new
    @ran_this_run = Set.new
    @handler_problems = {}
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
    @concurrent_progress = Archsight::Import::ConcurrentProgress.new(max_slots: @max_concurrent, output: @output)
    @shared_writer = Archsight::Import::SharedFileWriter.new

    # Set up graceful shutdown on Ctrl-C
    setup_signal_handlers

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
      reload_and_update_total! if need_reload

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

    # Raise InterruptedError if we were interrupted, so CLI can handle it
    raise Archsight::Import::InterruptedError, "Import interrupted by user" if @interrupted
  ensure
    restore_signal_handlers
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

    # Apply filter if specified
    filtered_imports = all_imports.select { |imp| import_matches_filter?(imp) }

    # Topological sort
    sorted = topological_sort(filtered_imports)

    @output.puts "Filter: #{@filter}" if @filter
    @output.puts "Dependencies: not run (--no-deps)" if only_matches?

    sorted.each_with_index do |imp, idx|
      enabled = import_enabled?(imp)
      deps = import_dependency_names(imp)
      deps_str = deps.empty? ? "(no dependencies)" : "depends on: #{deps.join(", ")}"
      enabled_str = enabled ? "" : " [DISABLED]"
      @output.puts "  #{idx + 1}. #{imp.name}#{enabled_str} #{deps_str}#{unmatched_patterns_note(imp)}"
    end

    sorted
  end

  # Names of the imports that executed in this run (not served from the cache)
  def ran_imports
    @mutex.synchronize { @ran_this_run.to_a.sort }
  end

  private

  # Set up signal handlers for graceful shutdown
  def setup_signal_handlers
    @original_int_handler = Signal.trap("INT") do
      if @interrupted
        # Second Ctrl-C: force exit
        # Use trap-safe method (no mutex) since we're in signal context
        @concurrent_progress&.finish_from_trap("Force quit")
        @shared_writer&.close_all
        exit(130)
      else
        # First Ctrl-C: graceful shutdown
        @interrupted = true
        # Use trap-safe method (no mutex) since we're in signal context
        @concurrent_progress&.interrupt_from_trap("Shutting down gracefully (Ctrl-C again to force quit)...")
      end
    end
  end

  # Restore original signal handlers
  def restore_signal_handlers
    Signal.trap("INT", @original_int_handler || "DEFAULT")
  end

  # Count all enabled imports (for overall progress display)
  def count_all_enabled_imports
    imports = database.instances_by_kind("Import")&.values || []
    imports.count { |imp| import_enabled?(imp) && import_matches_filter?(imp) }
  end

  # Get all pending imports (enabled=true, not yet executed this run, matches filter)
  def pending_imports
    imports = database.instances_by_kind("Import")&.values || []

    @mutex.synchronize do
      imports.select do |imp|
        import_enabled?(imp) && import_matches_filter?(imp) && !@executed_this_run.include?(imp.name)
      end
    end
  end

  # Check if import is enabled and has a handler
  def import_enabled?(import)
    import.annotations["import/enabled"] != "false" && import.annotations["import/handler"]
  end

  # Check if import matches the filter pattern (or is a dependency of a matching import)
  def import_matches_filter?(import)
    return true unless @filter_regex

    # Build the set of imports to run on first call (includes filtered + their dependencies)
    @imports_to_run ||= compute_imports_to_run
    @imports_to_run.include?(import.name)
  end

  # Whether only the imports matching the filter run (`-f` with `--no-deps`)
  def only_matches?
    !@deps && !@filter_regex.nil?
  end

  # Compute the full set of imports to run: filtered imports + all their dependencies (only the filtered ones with
  # `--no-deps`)
  def compute_imports_to_run
    all_imports = database.instances_by_kind("Import")&.values || []
    imports_by_name = all_imports.to_h { |imp| [imp.name, imp] }

    # Start with imports matching the filter
    matching = all_imports.select { |imp| @filter_regex.match?(imp.name) }.map(&:name)
    to_run = Set.new(matching)
    return to_run unless @deps

    # Recursively add dependencies
    queue = matching.dup
    while (name = queue.shift)
      import = imports_by_name[name]
      next unless import

      dep_names = import_dependency_names(import)
      dep_names.each do |dep_name|
        unless to_run.include?(dep_name)
          to_run.add(dep_name)
          queue << dep_name
        end
      end
    end

    to_run
  end

  # Check if all dependencies of an import are satisfied (executed successfully this run).
  # A parent that can never run (no handler or disabled, e.g. the repository was
  # deleted upstream and only its generated `generates` entry is left) is not
  # waited for, otherwise its children would deadlock the run.
  def dependencies_satisfied?(import)
    dep_names = runnable_dependency_names(import)
    return true if dep_names.empty?

    @mutex.synchronize do
      dep_names.all? do |dep_name|
        @executed_this_run.include?(dep_name) && !@failed_imports.key?(dep_name)
      end
    end
  end

  # With `--no-deps` a dependency outside the run is not waited for: it does not run, so the import uses the model
  # as it is
  def runnable_dependency_names(import)
    imports_by_name = (database.instances_by_kind("Import")&.values || []).to_h { |imp| [imp.name, imp] }
    import_dependency_names(import).select do |dep_name|
      parent = imports_by_name[dep_name]
      parent && import_enabled?(parent) && (!only_matches? || import_matches_filter?(parent))
    end
  end

  # Get dependency names for an import: the parents that generate it (the inverse of `generates` - if Import A
  # generates Import B, then B depends on A) and the imports it declares in `import/dependsOn`
  def import_dependency_names(import)
    all_imports = database.instances_by_kind("Import")&.values || []
    parent_imports = all_imports.select do |parent|
      generated_import_names(parent).include?(import.name)
    end
    (parent_imports.map(&:name) + declared_dependency_names(import, all_imports)).uniq
  end

  # The imports `import/dependsOn` names or matches. For a pattern this also includes the imports that may still
  # generate a matching import in this run: one whose last run generated a match, and one that never ran but whose
  # handler generates imports. So `Import:Repo:*` waits for the GitHub import and then for the repositories it found.
  def declared_dependency_names(import, all_imports = database.instances_by_kind("Import")&.values || [])
    entries = Archsight::Import.declared_dependencies(import)
    return [] if entries.empty?

    others = all_imports.reject { |imp| imp.name == import.name }
    entries.flat_map do |entry|
      matches = others.select { |imp| Archsight::Import.dependency_match?(entry, imp.name) }
      matches += others.select { |imp| may_generate_match?(imp, entry) } if Archsight::Import.pattern?(entry)
      matches.map(&:name)
    end.uniq
  end

  # Whether an import generated a match of the pattern in its last run, or may do so on its first one
  def may_generate_match?(import, pattern)
    generated = generated_import_names(import)
    return generated.any? { |name| Archsight::Import.dependency_match?(pattern, name) } if generated.any?

    handler = Archsight::Import::Registry[import.annotations["import/handler"]]
    !import.annotations["generated/at"] && handler.respond_to?(:generates_imports?) && handler.generates_imports?
  end

  def generated_import_names(import)
    (import.relations(:generates, :imports) || []).map { |gen| gen.is_a?(String) ? gen : gen.name }
  end

  # For the plan: patterns of `import/dependsOn` that match no import yet
  def unmatched_patterns_note(import)
    all_names = (database.instances_by_kind("Import")&.keys || []) - [import.name]
    unmatched = Archsight::Import.declared_dependencies(import).select do |entry|
      Archsight::Import.pattern?(entry) && all_names.none? { |name| Archsight::Import.dependency_match?(entry, name) }
    end
    unmatched.empty? ? "" : " (#{unmatched.join(", ")} matches no import yet)"
  end

  # Reload database without verbose output, and load the handlers the imports declare (`import/handlerPath`)
  def reload_database_quietly!
    original_verbose = database.verbose
    database.verbose = false
    database.reload!
    load_local_handlers
    # Reset filter cache since new imports may have been discovered
    @imports_to_run = nil if @filter_regex
  ensure
    database.verbose = original_verbose
  end

  # A handler file that does not load fails the imports that use it, not the whole run
  def load_local_handlers
    problems = Archsight::Import::HandlerLoader.load(database, resources_dir: resources_dir)
    @handler_problems = problems.to_h { |problem| [problem.import.name, problem.message] }
  end

  # Reload database and update progress total for newly discovered imports
  def reload_and_update_total!
    reload_database_quietly!
    new_total = count_all_enabled_imports
    @concurrent_progress.update_total(new_total) if new_total.positive?
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
          # Skip work queued before the interrupt — let already-running imports finish
          if @interrupted
            @mutex.synchronize { @executed_this_run.delete(imp.name) }
            slot_progress.complete("Skipped")
            next
          end

          result = execute_single_import(imp, slot_progress)
          if result == :cached
            slot_progress.complete("Cached")
          elsif result.is_a?(String)
            slot_progress.complete(result)
          else
            @mutex.synchronize { @total_executed += 1 }
            slot_progress.complete("Done")
          end
        rescue StandardError => e
          detail = [e.message, e.backtrace.first].compact.join(" @ ")
          @mutex.synchronize do
            @failed_imports[imp.name] = detail
            @first_error ||= { name: imp.name, message: detail }
          end
          slot_progress.error(detail)
        ensure
          # Update overall progress and release slot
          @concurrent_progress.increment_completed
          slot_progress.release
        end
      end
    end

    # Wait for all threads to complete
    threads.each(&:join)
  end

  # Execute a single import (called from thread)
  # @return [Symbol, String] :executed, :cached, a message for a skipped import, or raises on error
  def execute_single_import(import, import_progress)
    # Check if import is still fresh based on generated/at and import/cacheTime
    if import_fresh?(import)
      @mutex.synchronize { @total_cached += 1 }
      return :cached
    end

    problem = @handler_problems[import.name]
    raise Archsight::Import::UnknownHandlerError, problem if problem

    missing = missing_environment(import)
    if missing.any?
      message = "missing environment variable#{"s" if missing.length > 1} #{missing.join(", ")} (import/config/requiredEnv)"
      raise Archsight::Import::ImportError, message unless import.annotations["import/config/optional"] == "true"

      import_progress.warn("Skipped: #{message}")
      return "Skipped"
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
    remove_stale_outputs(import, handler.owned_outputs)
    @mutex.synchronize { @ran_this_run.add(import.name) }
    :executed
  end

  # Variables of `import/config/requiredEnv` that are not set (or blank)
  def missing_environment(import)
    names = import.annotations["import/config/requiredEnv"].to_s.split(",").map(&:strip).reject(&:empty?)
    names.select { |name| ENV[name].to_s.strip.empty? }
  end

  # Delete the files an earlier run of the import wrote (`generated/outputs`) that this run did not write again
  def remove_stale_outputs(import, written)
    previous = import.annotations["generated/outputs"].to_s.split(",").map(&:strip).reject(&:empty?)
    (previous - written).each do |rel_path|
      path = Archsight::Import.resources_path(resources_dir, rel_path)
      FileUtils.rm_f(path) if path && File.file?(path)
    end
  end

  # Check if import is still fresh (cached)
  # Uses generated/at annotation and import/cacheTime to determine freshness. The cache is also invalid when the
  # output file or a recorded output (`generated/outputs`) is missing, the configuration or the files of
  # `import/config/inputs` changed, or an import it declares in `import/dependsOn` executed in this run.
  def import_fresh?(import)
    # Honor force flag - always re-run when forced
    return false if @force

    cache_time = import.annotations["import/cacheTime"]
    return false if cache_time.nil? || cache_time.empty? || cache_time == "never"

    # Check if output file exists - if not, cache is invalid
    output_path = import.annotations["import/outputPath"]
    if output_path && !output_path.empty?
      full_path = File.join(resources_dir, output_path)
      return false unless File.exist?(full_path)
    end

    return false unless recorded_outputs_exist?(import)
    return false if dependency_ran?(import)
    return false if import.annotations["import/config/inputs"] &&
                    import.annotations["generated/inputsHash"] != Archsight::Import.inputs_hash(import, resources_dir)

    generated_at = import.annotations["generated/at"]
    return false if generated_at.nil? || generated_at.empty?

    ttl_seconds = parse_duration(cache_time)
    return false unless ttl_seconds

    last_run = Time.parse(generated_at)

    # Check if import configuration has changed since last generation
    # Compare stored config hash against current config hash
    stored_hash = import.annotations["generated/configHash"]
    if stored_hash
      current_hash = compute_config_hash(import)
      return false if current_hash != stored_hash
    end

    Time.now < (last_run + ttl_seconds)
  rescue ArgumentError
    # Invalid time format
    false
  end

  def recorded_outputs_exist?(import)
    import.annotations["generated/outputs"].to_s.split(",").map(&:strip).reject(&:empty?).all? do |rel_path|
      path = Archsight::Import.resources_path(resources_dir, rel_path)
      path && File.exist?(path)
    end
  end

  # Whether an import declared in `import/dependsOn` executed (not just came from the cache) in this run. The
  # generated imports of a parent are not affected: they keep their own cache time when the parent runs.
  def dependency_ran?(import)
    names = declared_dependency_names(import)
    @mutex.synchronize { names.any? { |name| @ran_this_run.include?(name) } }
  end

  def parse_duration(str)
    return nil if str.nil?

    DURATION_PATTERNS.each do |pattern, multiplier|
      match = str.match(pattern)
      return match[1].to_i * multiplier if match
    end

    nil
  end

  # Compute a hash of the import's configuration for cache invalidation
  # Includes handler and all import/config/* annotations
  def compute_config_hash(import)
    config_data = {
      handler: import.annotations["import/handler"],
      config: import.annotations.select { |k, _| k.start_with?("import/config/") }.sort.to_h
    }
    Digest::SHA256.hexdigest(config_data.to_json)[0, 16]
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

      # Visit dependencies first (derived from generates relation)
      dep_names = import_dependency_names(import)
      dep_names.each do |dep_name|
        dep = imports_by_name[dep_name]
        visit.call(dep) if dep
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

    @output.puts msg if verbose
  end
end

# Error raised when imports have circular or unsatisfied dependencies
class Archsight::Import::DeadlockError < StandardError; end

# Error raised when an import fails
class Archsight::Import::ImportError < StandardError; end

# Error raised when import is interrupted by user (Ctrl-C)
class Archsight::Import::InterruptedError < StandardError; end
