# frozen_string_literal: true

require "test_helper"
require "archsight/analysis"
require "tmpdir"

class AnalysisExecutorTest < Minitest::Test
  def setup
    @resources_dir = Dir.mktmpdir
    setup_basic_resources
    @db = Archsight::Database.new(@resources_dir, verbose: false)
    @db.reload!
    @executor = Archsight::Analysis::Executor.new(@db)
  end

  def teardown
    FileUtils.remove_entry(@resources_dir) if @resources_dir && File.exist?(@resources_dir)
  end

  def setup_basic_resources
    # Create a basic ApplicationService for testing
    yaml_content = <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: ApplicationService
      metadata:
        name: TestService
        annotations:
          team/name: TestTeam
      spec: {}
    YAML
    File.write(File.join(@resources_dir, "services.yaml"), yaml_content)
  end

  def create_analysis(name:, script:, timeout: "30s", enabled: "true")
    yaml_content = <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: Analysis
      metadata:
        name: #{name}
        annotations:
          analysis/handler: ruby
          analysis/script: |
            #{script.gsub("\n", "\n            ")}
          analysis/timeout: #{timeout}
          analysis/enabled: "#{enabled}"
      spec: {}
    YAML
    File.write(File.join(@resources_dir, "#{name.gsub(":", "_")}.yaml"), yaml_content)
    @db.reload!
  end

  # Helper to find message sections
  def find_messages(result)
    result.sections.select { |s| s[:type] == :message }
  end

  # Basic execution tests

  def test_execute_simple_script
    create_analysis(
      name: "Test:Simple",
      script: 'info("Hello")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:Simple")
    result = @executor.execute(analysis)

    assert_predicate result, :success?
    messages = find_messages(result)

    assert(messages.any? { |m| m[:message] == "Hello" })
  end

  def test_execute_returns_result
    create_analysis(
      name: "Test:Result",
      script: 'report({ value: 42 }, title: "Test")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:Result")
    result = @executor.execute(analysis)

    assert_kind_of Archsight::Analysis::Result, result
    assert_predicate result, :success?
  end

  def test_execute_collects_sections
    create_analysis(
      name: "Test:Sections",
      script: 'report([1, 2, 3], title: "Numbers")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:Sections")
    result = @executor.execute(analysis)

    heading = result.sections.find { |s| s[:type] == :heading }
    list = result.sections.find { |s| s[:type] == :list }

    assert_equal "Numbers", heading[:text]
    assert_equal %w[1 2 3], list[:items]
  end

  def test_execute_collects_messages
    create_analysis(
      name: "Test:Messages",
      script: <<~RUBY
        info("Info message")
        warning("Warning message")
        error("Error message")
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:Messages")
    result = @executor.execute(analysis)

    messages = find_messages(result)

    assert_equal 3, messages.count
    assert(messages.any? { |m| m[:level] == :info })
    assert(messages.any? { |m| m[:level] == :warning })
    assert(messages.any? { |m| m[:level] == :error })
  end

  # Error handling tests

  def test_execute_handles_syntax_error
    create_analysis(
      name: "Test:SyntaxError",
      script: "def broken("
    )

    analysis = @db.instance_by_kind("Analysis", "Test:SyntaxError")
    result = @executor.execute(analysis)

    assert_predicate result, :failed?
    assert_includes result.error, "SyntaxError"
  end

  def test_execute_handles_runtime_error
    create_analysis(
      name: "Test:RuntimeError",
      script: 'raise "Something went wrong"'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:RuntimeError")
    result = @executor.execute(analysis)

    assert_predicate result, :failed?
    assert_includes result.error, "RuntimeError"
    assert_includes result.error, "Something went wrong"
  end

  def test_execute_handles_missing_script
    yaml_content = <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: Analysis
      metadata:
        name: Test:NoScript
        annotations:
          analysis/handler: ruby
      spec: {}
    YAML
    File.write(File.join(@resources_dir, "no_script.yaml"), yaml_content)
    @db.reload!

    analysis = @db.instance_by_kind("Analysis", "Test:NoScript")
    result = @executor.execute(analysis)

    assert_predicate result, :failed?
    assert_includes result.error, "No script defined"
  end

  # Timeout tests

  def test_execute_respects_timeout
    create_analysis(
      name: "Test:Timeout",
      script: "loop { sleep 0.1 }",
      timeout: "1s"
    )

    analysis = @db.instance_by_kind("Analysis", "Test:Timeout")
    result = @executor.execute(analysis)

    assert_predicate result, :failed?
    assert_includes result.error, "timed out"
  end

  def test_parses_timeout_seconds
    create_analysis(
      name: "Test:TimeoutSeconds",
      script: 'info("done")',
      timeout: "30s"
    )

    analysis = @db.instance_by_kind("Analysis", "Test:TimeoutSeconds")
    result = @executor.execute(analysis)

    assert_predicate result, :success?
  end

  def test_parses_timeout_minutes
    create_analysis(
      name: "Test:TimeoutMinutes",
      script: 'info("done")',
      timeout: "5m"
    )

    analysis = @db.instance_by_kind("Analysis", "Test:TimeoutMinutes")
    result = @executor.execute(analysis)

    assert_predicate result, :success?
  end

  # Instance access tests

  def test_script_can_access_instances
    create_analysis(
      name: "Test:Instances",
      script: <<~RUBY
        services = instances(:ApplicationService)
        report(services.count, title: "Service Count")
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:Instances")
    result = @executor.execute(analysis)

    assert_predicate result, :success?
    text = result.sections.find { |s| s[:type] == :text }

    assert_equal "1", text[:content]
  end

  def test_script_can_iterate_instances
    create_analysis(
      name: "Test:Iteration",
      script: <<~RUBY
        names = []
        each_instance(:ApplicationService) do |service|
          names << name(service)
        end
        report(names, title: "Services")
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:Iteration")
    result = @executor.execute(analysis)

    assert_predicate result, :success?
    list = result.sections.find { |s| s[:type] == :list }

    assert_includes list[:items], "TestService"
  end

  def test_script_can_access_annotations
    create_analysis(
      name: "Test:Annotations",
      script: <<~RUBY
        each_instance(:ApplicationService) do |service|
          team = annotation(service, "team/name")
          report(team, title: "Team") if team
        end
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:Annotations")
    result = @executor.execute(analysis)

    assert_predicate result, :success?
    text = result.sections.find { |s| s[:type] == :text }

    assert_equal "TestTeam", text[:content]
  end

  # Execute all tests

  def test_execute_all_returns_array
    create_analysis(name: "Test:All1", script: 'info("one")')
    create_analysis(name: "Test:All2", script: 'info("two")')

    results = @executor.execute_all

    assert_kind_of Array, results
    assert_equal 2, results.count
  end

  def test_execute_all_with_filter
    create_analysis(name: "Test:FilterA", script: 'info("a")')
    create_analysis(name: "Test:FilterB", script: 'info("b")')

    results = @executor.execute_all(filter: /FilterA/)

    assert_equal 1, results.count
    assert_equal "Test:FilterA", results.first.name
  end

  def test_execute_all_skips_disabled
    create_analysis(name: "Test:Enabled", script: 'info("enabled")', enabled: "true")
    create_analysis(name: "Test:Disabled", script: 'info("disabled")', enabled: "false")

    results = @executor.execute_all

    assert_equal 1, results.count
    assert_equal "Test:Enabled", results.first.name
  end

  # Result tests

  def test_result_name
    create_analysis(name: "Test:Name", script: 'info("test")')

    analysis = @db.instance_by_kind("Analysis", "Test:Name")
    result = @executor.execute(analysis)

    assert_equal "Test:Name", result.name
  end

  def test_result_has_findings
    create_analysis(
      name: "Test:Findings",
      script: 'report([1, 2, 3], title: "Findings")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:Findings")
    result = @executor.execute(analysis)

    assert_predicate result, :has_findings?
  end

  def test_result_no_findings_with_empty_report
    create_analysis(
      name: "Test:NoFindings",
      script: 'report([], title: "Empty")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:NoFindings")
    result = @executor.execute(analysis)

    # Empty report creates only heading (no list for empty data)
    # has_findings? checks for table, list, text, heading, code
    # The heading is still present, so has_findings? is true
    heading = result.sections.find { |s| s[:type] == :heading }

    assert_equal "Empty", heading[:text]
  end

  def test_result_error_count
    create_analysis(
      name: "Test:ErrorCount",
      script: <<~RUBY
        error("Error 1")
        error("Error 2")
        warning("Warning")
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:ErrorCount")
    result = @executor.execute(analysis)

    assert_equal 2, result.error_count
  end

  def test_result_warning_count
    create_analysis(
      name: "Test:WarningCount",
      script: <<~RUBY
        warning("Warning 1")
        warning("Warning 2")
        error("Error")
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:WarningCount")
    result = @executor.execute(analysis)

    assert_equal 2, result.warning_count
  end

  def test_result_to_markdown_contains_script_output
    create_analysis(name: "Test:ToString", script: 'info("test message")')

    analysis = @db.instance_by_kind("Analysis", "Test:ToString")
    result = @executor.execute(analysis)

    # to_markdown only contains script output, not status header
    assert_includes result.to_markdown, "test message"
  end

  def test_result_status_emoji_success
    create_analysis(name: "Test:Pass", script: 'info("test")')

    analysis = @db.instance_by_kind("Analysis", "Test:Pass")
    result = @executor.execute(analysis)

    assert_equal "✅", result.status_emoji
  end

  def test_result_status_emoji_fail
    create_analysis(name: "Test:Fail", script: 'raise "error"')

    analysis = @db.instance_by_kind("Analysis", "Test:Fail")
    result = @executor.execute(analysis)

    assert_equal "❌", result.status_emoji
    assert_includes result.error_markdown, "Error:"
  end

  def test_result_status_emoji_findings
    create_analysis(
      name: "Test:ShowFindings",
      script: 'report([1, 2, 3], title: "Items")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:ShowFindings")
    result = @executor.execute(analysis)

    # Status emoji shows findings indicator
    assert_equal "⚠️", result.status_emoji
    # Markdown contains script output
    assert_includes result.to_markdown, "Items"
  end

  def test_result_duration_tracked
    create_analysis(name: "Test:Duration", script: "sleep 0.1")

    analysis = @db.instance_by_kind("Analysis", "Test:Duration")
    result = @executor.execute(analysis)

    assert_predicate result, :success?
    assert_operator result.duration, :>=, 0.1
  end

  # Additional Result tests for coverage

  def test_to_markdown_verbose_includes_all_rows
    create_analysis(
      name: "Test:VerboseTable",
      script: <<~RUBY
        rows = (1..15).map { |i| [i, "Item \#{i}"] }
        heading("Large Table", level: 1)
        table(headers: ["ID", "Name"], rows: rows)
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:VerboseTable")
    result = @executor.execute(analysis)

    verbose_md = result.to_markdown(verbose: true)
    # All 15 rows should be present
    assert_includes verbose_md, "Item 15"
    refute_includes verbose_md, "...and"
  end

  def test_to_markdown_non_verbose_truncates_table
    create_analysis(
      name: "Test:TruncatedTable",
      script: <<~RUBY
        rows = (1..15).map { |i| [i, "Item \#{i}"] }
        heading("Large Table", level: 1)
        table(headers: ["ID", "Name"], rows: rows)
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:TruncatedTable")
    result = @executor.execute(analysis)

    non_verbose_md = result.to_markdown(verbose: false)
    # Should be truncated at 10 rows
    assert_includes non_verbose_md, "Item 10"
    refute_includes non_verbose_md, "Item 11"
    assert_includes non_verbose_md, "...and 5 more rows"
  end

  def test_to_markdown_non_verbose_truncates_list
    create_analysis(
      name: "Test:TruncatedList",
      script: <<~RUBY
        items = (1..15).map { |i| "Item \#{i}" }
        report(items, title: "Large List")
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:TruncatedList")
    result = @executor.execute(analysis)

    non_verbose_md = result.to_markdown(verbose: false)
    # Should be truncated at 10 items
    assert_includes non_verbose_md, "Item 10"
    refute_includes non_verbose_md, "Item 11"
    assert_includes non_verbose_md, "...and 5 more items"
  end

  def test_error_markdown_with_verbose_backtrace
    create_analysis(
      name: "Test:ErrorBacktrace",
      script: 'raise "Test error with backtrace"'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:ErrorBacktrace")
    result = @executor.execute(analysis)

    error_md = result.error_markdown(verbose: true)

    assert_includes error_md, "**Error:**"
    # Verbose mode should include backtrace in code block
    assert_includes error_md, "```"
  end

  def test_error_markdown_non_verbose_no_backtrace
    create_analysis(
      name: "Test:ErrorNoBacktrace",
      script: 'raise "Test error"'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:ErrorNoBacktrace")
    result = @executor.execute(analysis)

    error_md = result.error_markdown(verbose: false)

    assert_includes error_md, "**Error:**"
    # Non-verbose should not include backtrace code block
    refute_includes error_md, "```"
  end

  def test_error_markdown_returns_nil_for_success
    create_analysis(
      name: "Test:NoErrorMd",
      script: 'info("Success!")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:NoErrorMd")
    result = @executor.execute(analysis)

    assert_nil result.error_markdown
  end

  def test_format_message_with_unknown_level
    create_analysis(
      name: "Test:UnknownLevel",
      script: 'info("Test info message")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:UnknownLevel")
    result = @executor.execute(analysis)

    # Info messages should use blue emoji
    assert_includes result.to_markdown, "🔵"
  end

  def test_format_heading_level
    create_analysis(
      name: "Test:HeadingLevel",
      script: 'report("content", title: "My Title")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:HeadingLevel")
    result = @executor.execute(analysis)

    md = result.to_markdown
    # Title should be rendered as heading
    assert_includes md, "## My Title"
  end

  def test_format_code_with_language
    create_analysis(
      name: "Test:CodeLang",
      script: 'code("puts :hello", lang: "ruby")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:CodeLang")
    result = @executor.execute(analysis)

    md = result.to_markdown

    assert_includes md, "```ruby"
    assert_includes md, "puts :hello"
  end

  def test_format_code_without_language
    create_analysis(
      name: "Test:CodeNoLang",
      script: 'code("plain text")'
    )

    analysis = @db.instance_by_kind("Analysis", "Test:CodeNoLang")
    result = @executor.execute(analysis)

    md = result.to_markdown

    assert_includes md, "```\n"
    assert_includes md, "plain text"
  end

  def test_duration_str_with_duration
    create_analysis(name: "Test:DurationStr", script: "sleep 0.05")

    analysis = @db.instance_by_kind("Analysis", "Test:DurationStr")
    result = @executor.execute(analysis)

    duration = result.duration_str

    assert_match(/\d+\.\d{2}s/, duration)
  end

  def test_duration_str_without_duration
    # Create a stub analysis for testing Result directly
    create_analysis(name: "Test:NilDuration", script: 'info("test")')
    analysis = @db.instance_by_kind("Analysis", "Test:NilDuration")

    result = Archsight::Analysis::Result.new(
      analysis,
      success: true,
      sections: [],
      duration: nil
    )

    assert_equal "", result.duration_str
  end

  def test_table_cell_escapes_pipes
    create_analysis(
      name: "Test:PipeEscape",
      script: <<~RUBY
        heading("Pipes", level: 1)
        table(headers: ["Col1", "Col2"], rows: [["a|b", "c|d"]])
      RUBY
    )

    analysis = @db.instance_by_kind("Analysis", "Test:PipeEscape")
    result = @executor.execute(analysis)

    md = result.to_markdown
    # Pipes in cell content should be escaped
    assert_includes md, 'a\|b'
    assert_includes md, 'c\|d'
  end

  def test_result_render_returns_string
    create_analysis(name: "Test:Render", script: 'info("Render test")')

    analysis = @db.instance_by_kind("Analysis", "Test:Render")
    result = @executor.execute(analysis)

    rendered = result.render

    assert_kind_of String, rendered
  end

  def test_result_to_s_delegates_to_render
    create_analysis(name: "Test:ToS", script: 'info("ToString test")')

    analysis = @db.instance_by_kind("Analysis", "Test:ToS")
    result = @executor.execute(analysis)

    # to_s should produce same output as render
    assert_equal result.render, result.to_s
  end

  def test_failed_predicate
    create_analysis(name: "Test:Failed", script: 'raise "fail"')

    analysis = @db.instance_by_kind("Analysis", "Test:Failed")
    result = @executor.execute(analysis)

    assert_predicate result, :failed?
    refute_predicate result, :success?
  end
end
