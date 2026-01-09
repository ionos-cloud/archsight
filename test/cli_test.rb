# frozen_string_literal: true

require "test_helper"
require "archsight/cli"
require "stringio"
require "tempfile"

class CLITest < Minitest::Test
  def setup
    @resources_dir = File.expand_path("../examples/archsight", __dir__)
    @cli = Archsight::CLI.new
  end

  def test_version_outputs_version
    output = capture_stdout { @cli.version }

    assert_includes output, "archsight"
    assert_includes output, Archsight::VERSION
  end

  def test_template_without_kind_lists_kinds
    output = capture_stdout { @cli.template }

    assert_includes output, "Available resource kinds"
    assert_includes output, "TechnologyArtifact"
  end

  def test_template_with_kind_generates_yaml
    output = capture_stdout { @cli.template("TechnologyArtifact") }

    assert_includes output, "apiVersion: architecture/v1alpha1"
    assert_includes output, "kind: TechnologyArtifact"
  end

  def test_list_kinds_outputs_all_kinds
    output = capture_stdout { @cli.send(:list_kinds) }

    assert_includes output, "TechnologyArtifact"
    assert_includes output, "BusinessProduct"
  end

  def test_display_error_with_context_plain_message
    output = capture_stdout do
      @cli.send(:display_error_with_context, "Just a plain error message")
    end

    assert_includes output, "Just a plain error message"
  end

  def test_show_file_context_with_valid_file
    Tempfile.create(["test", ".yaml"]) do |f|
      5.times { |i| f.puts "line #{i + 1}" }
      f.flush

      output = capture_stdout do
        @cli.send(:show_file_context, f.path, 3)
      end

      assert_includes output, "line 3"
    end
  end

  def test_show_file_context_with_nonexistent_file
    output = capture_stdout do
      @cli.send(:show_file_context, "/nonexistent/file.yaml", 1)
    end

    assert_empty output
  end

  def test_configure_resources_sets_resources_dir
    original_dir = Archsight.resources_dir
    @cli.options = { resources: "/custom/path" }
    @cli.send(:configure_resources)

    assert_equal "/custom/path", Archsight.resources_dir
  ensure
    Archsight.resources_dir = original_dir
  end

  def test_lint_command_with_valid_resources
    original_dir = Archsight.resources_dir
    @cli.options = { resources: @resources_dir }

    output = capture_stdout { @cli.lint }

    assert_includes output, "passed"
  ensure
    Archsight.resources_dir = original_dir
  end

  def test_template_with_invalid_kind
    # Template.generate raises RuntimeError for invalid kinds
    assert_raises(RuntimeError) do
      @cli.template("InvalidKindXYZ")
    end
  end

  def test_display_error_with_file_context
    Tempfile.create(["test", ".yaml"]) do |f|
      5.times { |i| f.puts "line #{i + 1}" }
      f.flush

      error_string = "#{f.path}:3: Some error occurred"
      output = capture_stdout do
        @cli.send(:display_error_with_context, error_string)
      end

      assert_includes output, "line 3"
      assert_includes output, ">>"
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
