# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/diagram/cli"
require "tmpdir"

class DiagramCliTest < Minitest::Test
  def test_renders_multiple_input_files_in_one_invocation_each_to_its_own_default_output
    Dir.mktmpdir do |dir|
      a = write(dir, "a.asd", %(component "x" { }\n))
      b = write(dir, "b.asd", %(component "y" { }\n))

      status = nil
      stdout, = silence { status = Archsight::Diagram::CLI.run([a, b]) }

      assert_equal 0, status
      assert_same true, File.exist?(File.join(dir, "a.svg"))
      assert_same true, File.exist?(File.join(dir, "b.svg"))
      assert_includes stdout, "a.svg"
      assert_includes stdout, "b.svg"
    end
  end

  def test_rejects_o_output_when_given_more_than_one_input_file
    Dir.mktmpdir do |dir|
      a = write(dir, "a.asd", %(component "x" { }\n))
      b = write(dir, "b.asd", %(component "y" { }\n))

      status = nil
      _, stderr = silence { status = Archsight::Diagram::CLI.run([a, b, "-o", File.join(dir, "out.svg")]) }

      assert_equal 1, status
      assert_includes stderr, "single input file"
    end
  end

  def test_renders_the_remaining_files_and_reports_failure_when_one_input_is_invalid
    Dir.mktmpdir do |dir|
      good = write(dir, "good.asd", %(component "x" { }\n))
      bad = write(dir, "bad.asd", "not valid diagram source\n")

      status = nil
      _, stderr = silence { status = Archsight::Diagram::CLI.run([good, bad]) }

      assert_equal 1, status
      assert_same true, File.exist?(File.join(dir, "good.svg"))
      assert_same false, File.exist?(File.join(dir, "bad.svg"))
      assert_includes stderr, "bad.asd"
    end
  end

  def test_still_supports_a_single_input_file_with_an_explicit_o_output_path
    Dir.mktmpdir do |dir|
      a = write(dir, "a.asd", %(component "x" { }\n))
      out = File.join(dir, "custom.svg")

      status = nil
      silence { status = Archsight::Diagram::CLI.run([a, "-o", out]) }

      assert_equal 0, status
      assert_same true, File.exist?(out)
    end
  end

  def test_supports_style_none_to_omit_the_generated_presentation_stylesheet
    Dir.mktmpdir do |dir|
      a = write(dir, "a.asd", %(component "x" { }\n))

      status = nil
      silence { status = Archsight::Diagram::CLI.run([a, "--style", "none"]) }

      assert_equal 0, status
      svg = File.read(File.join(dir, "a.svg"))

      refute_includes svg, ".asd-fs-13" # the presentation stylesheet -- gone
    end
  end

  def test_supports_style_url_to_link_an_external_stylesheet_instead_of_embedding_the_presentation_rules
    Dir.mktmpdir do |dir|
      a = write(dir, "a.asd", %(component "x" { }\n))

      status = nil
      silence { status = Archsight::Diagram::CLI.run([a, "--style", "https://example.com/theme.css"]) }

      assert_equal 0, status
      svg = File.read(File.join(dir, "a.svg"))

      refute_includes svg, ".asd-fs-13"
      assert_includes svg, '<?xml-stylesheet type="text/css" href="https://example.com/theme.css"?>'
    end
  end

  def test_prints_usage_and_fails_when_no_input_files_are_given
    status = nil
    _, stderr = silence { status = Archsight::Diagram::CLI.run([]) }

    assert_equal 1, status
    assert_includes stderr, "missing input file"
  end

  def test_theme_flag_overrides_the_file_s_own_theme_statement
    Dir.mktmpdir do |dir|
      a = write(dir, "a.asd", %(theme "default"\ncomponent "x" { }\n))

      status = nil
      silence { status = Archsight::Diagram::CLI.run([a, "--theme=compact"]) }

      assert_equal 0, status
      assert_includes File.read(File.join(dir, "a.svg")), ".asd-fs-10"
    end
  end

  def test_legend_flag_overrides_the_file_s_own_legend_statement
    Dir.mktmpdir do |dir|
      a = write(dir, "a.asd", %(legend "right"\ndatabase "x" { }\ncomponent "y" { }\n))

      silence { Archsight::Diagram::CLI.run([a]) }

      assert_includes File.read(File.join(dir, "a.svg")), %(data-asd-side="right")
      silence { Archsight::Diagram::CLI.run([a, "--legend=none"]) }

      refute_includes File.read(File.join(dir, "a.svg")), %(id="asd-legend")
    end
  end

  def test_rejects_an_unknown_legend_flag_with_usage
    status = nil
    _, stderr = silence { status = Archsight::Diagram::CLI.run(["a.asd", "--legend=middle"]) }

    assert_equal 1, status
    assert_includes stderr, "invalid argument: --legend=middle"
  end

  def test_rejects_an_unknown_theme_flag_with_usage
    status = nil
    _, stderr = silence { status = Archsight::Diagram::CLI.run(["a.asd", "--theme=tiny"]) }

    assert_equal 1, status
    assert_includes stderr, "invalid argument: --theme=tiny"
    assert_includes stderr, "Usage:"
  end

  private

  def write(dir, name, content)
    path = File.join(dir, name)
    File.write(path, content)
    path
  end

  def silence
    original_stdout = $stdout
    original_stderr = $stderr
    original_verbose = $VERBOSE
    $VERBOSE = false # test_helper sets nil, which turns Kernel#warn into a no-op
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    [$stdout.string, $stderr.string]
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
    $VERBOSE = original_verbose
  end
end
