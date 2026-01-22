# frozen_string_literal: true

# Manages concurrent progress output with slot-based display
#
# In TTY mode: Each slot gets its own line, updated in place using ANSI codes with colors
# In non-TTY mode: Each update prints on its own line with context prefix (no colors)
class Archsight::Import::ConcurrentProgress
  # ANSI color codes
  COLORS = {
    reset: "\e[0m",
    bold: "\e[1m",
    dim: "\e[2m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    red: "\e[31m"
  }.freeze

  # ANSI cursor control
  CURSOR_HIDE = "\e[?25l"
  CURSOR_SHOW = "\e[?25h"
  CURSOR_SAVE = "\e[s"
  CURSOR_RESTORE = "\e[u"

  def initialize(max_slots:, output: $stdout)
    @output = output
    @tty = output.respond_to?(:tty?) && output.tty?
    @max_slots = max_slots
    @mutex = Mutex.new
    @slots = {}
    @slot_queue = Queue.new
    @lines_printed = 0

    # Overall progress tracking
    @total_imports = 0
    @completed_imports = 0
    @has_overall_line = false
    @start_time = nil

    # Initialize slot queue
    max_slots.times { |i| @slot_queue << i }
  end

  def tty?
    @tty
  end

  # Initialize total number of imports for overall progress
  def total=(total)
    @mutex.synchronize do
      @total_imports = total
      @completed_imports = 0
      @start_time = Time.now
      if @tty && !@has_overall_line
        # Save cursor position and hide cursor for clean display
        @output.print CURSOR_SAVE
        @output.print CURSOR_HIDE
        @output.puts build_overall_line
        @has_overall_line = true
        @lines_printed += 1
      end
    end
  end

  # Update total without resetting completed count (for multi-stage imports)
  def update_total(total)
    @mutex.synchronize do
      @total_imports = total
      update_overall_line if @tty && @has_overall_line
    end
  end

  # Increment completed count and update overall progress
  def increment_completed
    @mutex.synchronize do
      @completed_imports += 1
      update_overall_line if @tty && @has_overall_line
    end
  end

  # Acquire a slot for a new task
  # @return [SlotProgress] A progress reporter for this slot
  def acquire_slot(context)
    slot_id = @slot_queue.pop
    slot = SlotProgress.new(self, slot_id, context)

    @mutex.synchronize do
      @slots[slot_id] = slot
      # Slot lines start after the overall progress line (if present)
      effective_line = @has_overall_line ? slot_id + 1 : slot_id
      if @tty && effective_line >= @lines_printed
        # Print empty lines to reserve space
        (@lines_printed..effective_line).each { @output.puts }
        @lines_printed = effective_line + 1
      end
    end

    slot
  end

  # Release a slot back to the pool
  def release_slot(slot_id)
    @mutex.synchronize do
      @slots.delete(slot_id)
    end
    @slot_queue << slot_id
  end

  # Update a specific slot's display
  def update_slot(slot_id, context, message, current: nil, total: nil, color: nil)
    line = build_line(context, message, current, total, color: color)

    @mutex.synchronize do
      if @tty
        # Move cursor to slot line and update (account for overall progress line)
        effective_line = @has_overall_line ? slot_id + 1 : slot_id
        lines_up = @lines_printed - effective_line
        @output.print "\e[#{lines_up}A" # Move up
        @output.print "\e[2K"           # Clear line
        @output.print line
        @output.print "\e[#{lines_up}B" # Move back down
        @output.print "\r"              # Return to start of line
        @output.flush
      else
        @output.puts line
      end
    end
  end

  # Mark a slot as complete
  def complete_slot(slot_id, context, message = nil)
    @mutex.synchronize do
      if @tty
        effective_line = @has_overall_line ? slot_id + 1 : slot_id
        lines_up = @lines_printed - effective_line
        @output.print "\e[#{lines_up}A"
        @output.print "\e[2K"
        msg = message || "Done"
        @output.print "#{COLORS[:bold]}#{context}#{COLORS[:reset]} - #{COLORS[:green]}#{msg}#{COLORS[:reset]}"
        @output.print "\e[#{lines_up}B"
        @output.print "\r"
        @output.flush
      elsif message
        @output.puts "#{context} - #{message}"
      end
    end
  end

  # Report an error for a slot
  def error_slot(slot_id, context, message)
    safe_message = sanitize_message(message)
    @mutex.synchronize do
      if @tty
        effective_line = @has_overall_line ? slot_id + 1 : slot_id
        lines_up = @lines_printed - effective_line
        @output.print "\e[#{lines_up}A"
        @output.print "\e[2K"
        @output.print "#{COLORS[:bold]}#{context}#{COLORS[:reset]} - #{COLORS[:red]}Error: #{safe_message}#{COLORS[:reset]}"
        @output.print "\e[#{lines_up}B"
        @output.print "\r"
        @output.flush
      else
        @output.puts "#{context} - Error: #{safe_message}"
      end
    end
  end

  # Sanitize message to prevent breaking TTY display (remove newlines, truncate)
  def sanitize_message(message)
    return "" if message.nil?

    # Replace newlines with spaces and collapse multiple spaces
    clean = message.to_s.gsub(/[\r\n]+/, " ").gsub(/\s+/, " ").strip
    # Truncate if too long
    clean.length > 80 ? "#{clean[0, 77]}..." : clean
  end

  # Print a final summary (restores cursor and shows it)
  # Note: Use finish_from_trap when called from a signal handler
  def finish(message)
    @mutex.synchronize do
      finish_unsafe(message)
    end
  end

  # Trap-safe version of finish (no mutex, safe to call from signal handlers)
  def finish_from_trap(message)
    finish_unsafe(message)
  end

  # Show interrupt message without clearing progress (called on first Ctrl-C)
  # Note: Use interrupt_from_trap when called from a signal handler
  def interrupt(message)
    @mutex.synchronize do
      interrupt_unsafe(message)
    end
  end

  # Trap-safe version of interrupt (no mutex, safe to call from signal handlers)
  def interrupt_from_trap(message)
    interrupt_unsafe(message)
  end

  private

  def finish_unsafe(message)
    if @tty
      # Restore cursor position and show cursor
      @output.print CURSOR_RESTORE
      # Clear from cursor to end of screen to remove progress lines
      @output.print "\e[J"
      @output.print CURSOR_SHOW
    end
    @output.puts message if message
  end

  def interrupt_unsafe(message)
    if @tty
      # Move to the line below progress and print message
      @output.print "\n"
      @output.print "\e[2K"
      @output.print "#{COLORS[:yellow]}#{message}#{COLORS[:reset]}"
      @output.print "\n"
      @output.flush
      # Increase lines printed to account for the interrupt message
      @lines_printed += 2
    else
      @output.puts message
    end
  end

  def build_overall_line
    percentage = @total_imports.positive? ? ((@completed_imports.to_f / @total_imports) * 100).round : 0
    progress_bar = build_progress_bar(percentage)
    eta_str = calculate_eta_string
    if @tty
      "#{COLORS[:bold]}#{COLORS[:magenta]}Overall#{COLORS[:reset]} #{progress_bar} " \
        "#{COLORS[:cyan]}#{percentage}%#{COLORS[:reset]} " \
        "[#{@completed_imports}/#{@total_imports}] " \
        "#{COLORS[:dim]}#{eta_str}#{COLORS[:reset]}"
    else
      "Overall: [#{@completed_imports}/#{@total_imports}] #{percentage}% #{eta_str}"
    end
  end

  def calculate_eta_string
    return "ETA: --:--" if @start_time.nil? || @completed_imports.zero?

    elapsed = Time.now - @start_time
    remaining = @total_imports - @completed_imports
    rate = @completed_imports.to_f / elapsed
    eta_seconds = (remaining / rate).round

    if eta_seconds < 60
      "ETA: #{eta_seconds}s"
    elsif eta_seconds < 3600
      minutes = eta_seconds / 60
      seconds = eta_seconds % 60
      format("ETA: %d:%02d", minutes, seconds)
    else
      hours = eta_seconds / 3600
      minutes = (eta_seconds % 3600) / 60
      format("ETA: %d:%02d:%02d", hours, minutes, eta_seconds % 60)
    end
  end

  def build_progress_bar(percentage)
    width = 20
    filled = [(percentage / 5.0).round, width].min
    filled = [filled, 0].max
    empty = width - filled
    bar = "#{"█" * filled}#{"░" * empty}"
    "#{COLORS[:green]}#{bar}#{COLORS[:reset]}"
  end

  def update_overall_line
    # Move to first line (overall progress line), update, move back
    lines_up = @lines_printed
    @output.print "\e[#{lines_up}A"
    @output.print "\e[2K"
    @output.print build_overall_line
    @output.print "\e[#{lines_up}B"
    @output.print "\r"
    @output.flush
  end

  def build_line(context, message, current, total, color: nil)
    parts = []
    if @tty
      parts << "#{COLORS[:bold]}#{context}#{COLORS[:reset]}"
      parts << "#{COLORS[:cyan]}#{progress_indicator(current, total)}#{COLORS[:reset]}" if current && total
      msg_color = color || COLORS[:reset]
      parts << "#{msg_color}#{message}#{COLORS[:reset]}"
    else
      parts << context
      parts << progress_indicator(current, total) if current && total
      parts << message
    end
    parts.join(" - ")
  end

  def progress_indicator(current, total)
    percentage = ((current.to_f / total) * 100).round
    "[#{current}/#{total} #{percentage}%]"
  end

  # Individual slot progress reporter
  class SlotProgress
    attr_reader :slot_id
    attr_accessor :context

    def initialize(parent, slot_id, context)
      @parent = parent
      @slot_id = slot_id
      @context = context
    end

    def update(message, current: nil, total: nil)
      @parent.update_slot(@slot_id, @context, message, current: current, total: total)
    end

    def complete(message = nil)
      @parent.complete_slot(@slot_id, @context, message)
    end

    def error(message)
      @parent.error_slot(@slot_id, @context, message)
    end

    def warn(message)
      # Warnings are shown inline with the current context (yellow in TTY mode)
      @parent.update_slot(@slot_id, @context, "Warning: #{message}", color: COLORS[:yellow])
    end

    def release
      @parent.release_slot(@slot_id)
    end
  end
end
