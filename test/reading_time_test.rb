# frozen_string_literal: true

require "test_helper"
require "archsight/reading_time"

class ReadingTimeTest < Minitest::Test
  ASD = <<~ASD
    ```asd
    component "a" { label "A" }
    component "b" { label "B" }
    a -> b { relation "uses" }
    ```
  ASD

  def estimate(markdown, **)
    Archsight::ReadingTime.estimate(markdown, **)
  end

  def test_empty_page_takes_one_minute
    assert_equal({ minutes: 1, words: 0, diagrams: 0 }, estimate(""))
  end

  def test_words_set_the_minutes_rounded_up
    assert_equal 1, estimate("word " * 200)[:minutes]
    assert_equal 2, estimate("word " * 201)[:minutes]
    assert_equal 400, estimate("word " * 400)[:words]
  end

  def test_markup_links_and_images_are_not_words
    result = estimate("![img](a.png) https://example.com/x {status:green OK} <b>hi</b> there")

    assert_equal 2, result[:words] # hi, there
  end

  def test_code_counts_less_than_prose
    prose = estimate("word " * 600)[:minutes]
    code = estimate("```ruby\n#{"word " * 600}\n```")[:minutes]

    assert_operator code, :<, prose
    assert_equal 0, estimate("```ruby\nx y z\n```")[:words]
  end

  def test_asd_blocks_add_time_by_size
    plain = estimate("word " * 200)
    with_diagram = estimate("#{"word " * 200}\n\n#{ASD}")
    big = estimate("#{"word " * 200}\n\n```asd\n#{(1..40).map { |i| %(component "n#{i}" { label "N#{i}" }) }.join("\n")}\n```\n")

    assert_equal 1, with_diagram[:diagrams]
    assert_equal 0, with_diagram[:words] - plain[:words]
    assert_operator with_diagram[:minutes], :>, plain[:minutes]
    assert_operator big[:minutes], :>, with_diagram[:minutes]
  end

  def test_broken_diagram_does_not_raise
    result = estimate("```asd\nthis is not ( valid\n```\n")

    assert_equal 1, result[:diagrams]
    assert_equal 1, result[:minutes]
  end

  def test_embedded_asd_file_counts
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "d.asd"), %(component "a" { label "A" }\ncomponent "b" { label "B" }\na -> b { relation "uses" }\n))
      result = estimate("![](d.asd)", base_dir: "", resources_dir: dir)

      assert_equal 1, result[:diagrams]
    end
  end
end
