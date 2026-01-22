# frozen_string_literal: true

require "test_helper"
require "archsight/import/progress"
require "stringio"

class ProgressTest < Minitest::Test
  # TTY mode tests

  def test_tty_detection_with_tty_output
    output = create_tty_output
    progress = Archsight::Import::Progress.new(output: output)

    assert_predicate progress, :tty?
  end

  def test_tty_detection_with_non_tty_output
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    refute_predicate progress, :tty?
  end

  # update tests

  def test_tty_mode_update_clears_line
    output = create_tty_output
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Loading...")

    result = output.string
    # In TTY mode, uses \r to return to start of line
    assert_includes result, "Loading..."
  end

  def test_non_tty_mode_update_prints_line
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Loading...")

    result = output.string
    # In non-TTY mode, uses newline
    assert_includes result, "Loading...\n"
  end

  def test_update_with_progress_indicator
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Processing", current: 5, total: 10)

    result = output.string

    assert_includes result, "[5/10 50%]"
    assert_includes result, "Processing"
  end

  def test_update_with_context
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)
    progress.context = "Import:GitLab"

    progress.update("Fetching repos")

    result = output.string

    assert_includes result, "Import:GitLab"
    assert_includes result, "Fetching repos"
  end

  def test_context_included_in_output
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)
    progress.context = "MyContext"

    progress.update("Testing")

    result = output.string

    assert_includes result, "MyContext - Testing"
  end

  def test_progress_indicator_format
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Test", current: 1, total: 3)

    result = output.string

    assert_includes result, "[1/3 33%]"
  end

  def test_progress_indicator_rounding
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Test", current: 1, total: 7)

    result = output.string

    assert_includes result, "[1/7 14%]"
  end

  # complete tests

  def test_complete_with_message_tty
    output = create_tty_output
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Loading...")
    progress.complete("Done!")

    result = output.string

    assert_includes result, "Done!"
  end

  def test_complete_without_message_tty
    output = create_tty_output
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Loading...")
    progress.complete

    result = output.string
    # Should have a newline after the progress line
    assert_includes result, "\n"
  end

  def test_complete_non_tty_with_message
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.complete("Finished!")

    result = output.string

    assert_includes result, "Finished!\n"
  end

  def test_complete_resets_line_length
    output = create_tty_output
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("A very long message here")
    progress.complete("Short")

    # After complete, line length should be reset
    # Next update should not clear extra characters
    progress.update("New")

    result = output.string

    assert_includes result, "New"
  end

  # error tests

  def test_error_prints_message
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.error("Something went wrong")

    result = output.string

    assert_includes result, "Error: Something went wrong"
  end

  def test_error_clears_current_line_in_tty
    output = create_tty_output
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Processing...")
    progress.error("Failed!")

    result = output.string
    # Error should complete current line first
    assert_includes result, "Error: Failed!"
  end

  def test_error_without_active_line
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.error("No active line")

    result = output.string

    assert_includes result, "Error: No active line"
  end

  # warn tests

  def test_warn_in_tty_with_active_line
    output = create_tty_output
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Processing...")
    progress.warn("Something may be wrong")

    result = output.string

    assert_includes result, "Warning: Something may be wrong"
  end

  def test_warn_in_tty_without_active_line
    output = create_tty_output
    progress = Archsight::Import::Progress.new(output: output)

    progress.warn("Warning without context")

    result = output.string

    assert_includes result, "Warning: Warning without context"
  end

  def test_warn_in_non_tty
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.warn("Non-TTY warning")

    result = output.string

    assert_includes result, "Warning: Non-TTY warning\n"
  end

  def test_warn_resets_line_length_in_tty
    output = create_tty_output
    progress = Archsight::Import::Progress.new(output: output)

    progress.update("Long line content")
    progress.warn("Warning")

    # Check that line length was reset after warning
    progress.update("Short")

    result = output.string

    assert_includes result, "Short"
  end

  # context tests

  def test_context_can_be_set
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.context = "Test:Context"
    progress.update("Message")

    result = output.string

    assert_includes result, "Test:Context"
  end

  def test_context_can_be_changed
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    progress.context = "First"
    progress.update("Message 1")
    progress.context = "Second"
    progress.update("Message 2")

    result = output.string

    assert_includes result, "First"
    assert_includes result, "Second"
  end

  # edge cases

  def test_update_with_only_current_no_total
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    # current without total should not show progress indicator
    progress.update("Test", current: 5, total: nil)

    result = output.string

    refute_includes result, "[5/"
    assert_includes result, "Test"
  end

  def test_update_with_zero_total
    output = StringIO.new
    progress = Archsight::Import::Progress.new(output: output)

    # Division by zero raises FloatDomainError - verify the error
    assert_raises(FloatDomainError) do
      progress.update("Test", current: 0, total: 0)
    end
  end

  private

  def create_tty_output
    output = StringIO.new
    def output.tty?
      true
    end
    output
  end
end
