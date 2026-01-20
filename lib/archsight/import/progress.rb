# frozen_string_literal: true

# Progress reporter for import operations
#
# In TTY mode: updates a single line with \r
# In non-TTY mode (CI): prints each update on a new line
class Archsight::Import::Progress
  def initialize(output: $stdout)
    @output = output
    @tty = output.respond_to?(:tty?) && output.tty?
    @last_line_length = 0
    @current_context = nil
  end

  def tty?
    @tty
  end

  # Set the current context (e.g., "Import:GitLab")
  def context=(name)
    @current_context = name
  end

  # Report progress with optional sub-progress
  # Examples:
  #   update("Fetching projects...")
  #   update("Cloning", current: 5, total: 100)
  def update(message, current: nil, total: nil)
    line = build_line(message, current, total)

    if @tty
      # Clear previous line and write new one
      clear = "\r#{" " * @last_line_length}\r"
      @output.print "#{clear}#{line}"
      @output.flush
      @last_line_length = line.length
    else
      @output.puts line
    end
  end

  # Complete the current operation (moves to new line in TTY mode)
  def complete(message = nil)
    if message
      line = build_line(message)
      if @tty
        clear = "\r#{" " * @last_line_length}\r"
        @output.puts "#{clear}#{line}"
      else
        @output.puts line
      end
    elsif @tty
      @output.puts
    end
    @last_line_length = 0
  end

  # Report an error
  def error(message)
    complete if @tty && @last_line_length.positive?
    @output.puts "  Error: #{message}"
  end

  # Report a warning
  def warn(message)
    if @tty && @last_line_length.positive?
      # Save current line, print warning, restore
      @output.puts
      @output.puts "  Warning: #{message}"
      @last_line_length = 0
    else
      @output.puts "  Warning: #{message}"
    end
  end

  private

  def build_line(message, current = nil, total = nil)
    parts = []
    parts << @current_context if @current_context
    parts << progress_indicator(current, total) if current && total
    parts << message

    parts.join(" - ")
  end

  def progress_indicator(current, total)
    percentage = ((current.to_f / total) * 100).round
    "[#{current}/#{total} #{percentage}%]"
  end
end
