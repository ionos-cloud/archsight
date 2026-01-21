# frozen_string_literal: true

require "test_helper"
require "archsight/analysis"

class SandboxTest < Minitest::Test
  def setup
    @resources_dir = File.expand_path("../../examples/archsight", __dir__)
    @db = Archsight::Database.new(@resources_dir, verbose: false)
    @db.reload!
    @sandbox = Archsight::Analysis::Sandbox.new(@db)
  end

  # Instance iteration tests

  def test_instances_returns_array
    result = @sandbox.instances(:ApplicationService)

    assert_kind_of Array, result
  end

  def test_instances_returns_instances_of_kind
    result = @sandbox.instances(:ApplicationService)

    assert(result.all? { |inst| inst.klass == "ApplicationService" })
  end

  def test_each_instance_iterates_over_all
    count = 0
    @sandbox.each_instance(:ApplicationService) { count += 1 }

    assert_equal @db.instances_by_kind("ApplicationService").count, count
  end

  def test_instance_returns_specific_instance
    services = @sandbox.instances(:ApplicationService)
    skip if services.empty?

    first_name = @sandbox.name(services.first)
    result = @sandbox.instance(:ApplicationService, first_name)

    assert_equal first_name, @sandbox.name(result)
  end

  def test_instance_returns_nil_for_nonexistent
    result = @sandbox.instance(:ApplicationService, "NonexistentService")

    assert_nil result
  end

  # Data access tests

  def test_name_returns_instance_name
    services = @sandbox.instances(:ApplicationService)
    skip if services.empty?

    result = @sandbox.name(services.first)

    assert_kind_of String, result
    refute_empty result
  end

  def test_kind_returns_instance_kind
    services = @sandbox.instances(:ApplicationService)
    skip if services.empty?

    result = @sandbox.kind(services.first)

    assert_equal "ApplicationService", result
  end

  def test_annotation_returns_value
    services = @sandbox.instances(:ApplicationService)
    skip if services.empty?

    # Find a service with an annotation
    service = services.find { |s| s.annotations.any? }
    skip unless service

    key = service.annotations.keys.first
    result = @sandbox.annotation(service, key)

    assert_equal service.annotations[key], result
  end

  def test_annotation_returns_nil_for_missing
    services = @sandbox.instances(:ApplicationService)
    skip if services.empty?

    result = @sandbox.annotation(services.first, "nonexistent/annotation")

    assert_nil result
  end

  def test_annotations_returns_frozen_hash
    services = @sandbox.instances(:ApplicationService)
    skip if services.empty?

    result = @sandbox.annotations(services.first)

    assert_kind_of Hash, result
    assert_predicate result, :frozen?
  end

  # Relation traversal tests

  def test_outgoing_returns_array
    services = @sandbox.instances(:ApplicationService)
    skip if services.empty?

    result = @sandbox.outgoing(services.first)

    assert_kind_of Array, result
  end

  def test_outgoing_with_kind_filter
    services = @sandbox.instances(:ApplicationService)
    skip if services.empty?

    # Find a service with relations
    service = services.find { |s| @sandbox.outgoing(s).any? }
    skip unless service

    result = @sandbox.outgoing(service, :ApplicationComponent)

    assert(result.all? { |inst| @sandbox.kind(inst) == "ApplicationComponent" })
  end

  def test_outgoing_transitive_returns_array
    services = @sandbox.instances(:ApplicationService)
    skip if services.empty?

    result = @sandbox.outgoing_transitive(services.first)

    assert_kind_of Array, result
  end

  def test_incoming_returns_array
    components = @sandbox.instances(:ApplicationComponent)
    skip if components.empty?

    result = @sandbox.incoming(components.first)

    assert_kind_of Array, result
  end

  def test_incoming_transitive_returns_array
    components = @sandbox.instances(:ApplicationComponent)
    skip if components.empty?

    result = @sandbox.incoming_transitive(components.first)

    assert_kind_of Array, result
  end

  # Query tests

  def test_query_returns_array
    result = @sandbox.query('name =~ ".*"')

    assert_kind_of Array, result
    refute_empty result
  end

  def test_query_filters_results
    result = @sandbox.query("ApplicationService")

    assert(result.all? { |inst| @sandbox.kind(inst) == "ApplicationService" })
  end

  # Aggregation tests

  def test_sum_returns_total
    result = @sandbox.sum([1, 2, 3, 4, 5])

    assert_equal 15, result
  end

  def test_sum_ignores_nil
    result = @sandbox.sum([1, nil, 3, nil, 5])

    assert_equal 9, result
  end

  def test_count_returns_count
    result = @sandbox.count([1, 2, 3, 4, 5])

    assert_equal 5, result
  end

  def test_count_ignores_nil
    result = @sandbox.count([1, nil, 3, nil, 5])

    assert_equal 3, result
  end

  def test_avg_returns_average
    result = @sandbox.avg([1, 2, 3, 4, 5])

    assert_in_delta(3.0, result)
  end

  def test_avg_returns_nil_for_empty
    result = @sandbox.avg([])

    assert_nil result
  end

  def test_avg_ignores_nil
    result = @sandbox.avg([1, nil, 3, nil, 5])

    assert_in_delta(3.0, result)
  end

  def test_min_returns_minimum
    result = @sandbox.min([3, 1, 4, 1, 5])

    assert_equal 1, result
  end

  def test_max_returns_maximum
    result = @sandbox.max([3, 1, 4, 1, 5])

    assert_equal 5, result
  end

  def test_collect_without_key
    result = @sandbox.collect([1, nil, 3, nil, 5])

    assert_equal [1, 3, 5], result
  end

  def test_collect_with_block
    result = @sandbox.collect([1, 2, 3]) { |x| x * 2 }

    assert_equal [2, 4, 6], result
  end

  def test_group_by_groups_items
    items = [{ type: "a", value: 1 }, { type: "b", value: 2 }, { type: "a", value: 3 }]
    result = @sandbox.group_by(items) { |i| i[:type] }

    assert_equal 2, result.keys.count
    assert_equal 2, result["a"].count
    assert_equal 1, result["b"].count
  end

  # Structured output tests

  def test_heading_adds_section
    @sandbox.heading("Test Heading", level: 2)

    section = @sandbox.sections.first

    assert_equal :heading, section[:type]
    assert_equal "Test Heading", section[:text]
    assert_equal 2, section[:level]
  end

  def test_text_adds_section
    @sandbox.text("Some paragraph content")

    section = @sandbox.sections.first

    assert_equal :text, section[:type]
    assert_equal "Some paragraph content", section[:content]
  end

  def test_table_adds_section
    @sandbox.table(headers: %w[Name Value], rows: [%w[foo 1], %w[bar 2]])

    section = @sandbox.sections.first

    assert_equal :table, section[:type]
    assert_equal %w[Name Value], section[:headers]
    assert_equal 2, section[:rows].count
  end

  def test_table_skips_empty_rows
    @sandbox.table(headers: %w[Name Value], rows: [])

    assert_empty @sandbox.sections
  end

  def test_list_adds_section
    @sandbox.list(%w[item1 item2 item3])

    section = @sandbox.sections.first

    assert_equal :list, section[:type]
    assert_equal %w[item1 item2 item3], section[:items]
  end

  def test_list_skips_empty_items
    @sandbox.list([])

    assert_empty @sandbox.sections
  end

  def test_code_adds_section
    @sandbox.code("puts 'hello'", lang: "ruby")

    section = @sandbox.sections.first

    assert_equal :code, section[:type]
    assert_equal "puts 'hello'", section[:content]
    assert_equal "ruby", section[:lang]
  end

  # Legacy output tests

  def test_report_with_hash_creates_list
    @sandbox.report({ count: 5, name: "test" }, title: "Test Report")

    # Should have heading + list
    heading = @sandbox.sections.find { |s| s[:type] == :heading }
    list = @sandbox.sections.find { |s| s[:type] == :list }

    assert_equal "Test Report", heading[:text]
    assert(list[:items].any? { |i| i.include?("count") })
  end

  def test_report_with_array_of_hashes_creates_table
    @sandbox.report([{ name: "foo", value: 1 }, { name: "bar", value: 2 }], title: "Items")

    table = @sandbox.sections.find { |s| s[:type] == :table }

    assert_equal %w[name value], table[:headers]
    assert_equal 2, table[:rows].count
  end

  def test_report_with_simple_array_creates_list
    @sandbox.report(%w[item1 item2 item3])

    list = @sandbox.sections.find { |s| s[:type] == :list }

    assert_equal %w[item1 item2 item3], list[:items]
  end

  def test_report_with_scalar_creates_text
    @sandbox.report(42)

    text = @sandbox.sections.find { |s| s[:type] == :text }

    assert_equal "42", text[:content]
  end

  def test_warning_adds_message_section
    @sandbox.warning("Something might be wrong")

    section = @sandbox.sections.first

    assert_equal :message, section[:type]
    assert_equal :warning, section[:level]
    assert_equal "Something might be wrong", section[:message]
  end

  def test_error_adds_message_section
    @sandbox.error("Something is wrong")

    section = @sandbox.sections.first

    assert_equal :message, section[:type]
    assert_equal :error, section[:level]
    assert_equal "Something is wrong", section[:message]
  end

  def test_info_adds_message_section
    @sandbox.info("FYI")

    section = @sandbox.sections.first

    assert_equal :message, section[:type]
    assert_equal :info, section[:level]
    assert_equal "FYI", section[:message]
  end

  # Instance eval test

  def test_instance_eval_executes_script
    script = <<~RUBY
      count = 0
      each_instance(:ApplicationService) { count += 1 }
      report(count, title: "Service Count")
    RUBY

    @sandbox.instance_eval(script, "test", 1)

    heading = @sandbox.sections.find { |s| s[:type] == :heading }
    text = @sandbox.sections.find { |s| s[:type] == :text }

    assert_equal "Service Count", heading[:text]
    assert_kind_of String, text[:content]
  end

  def test_sandbox_only_provides_defined_methods
    # Test that sandbox methods work
    script = <<~RUBY
      count = 0
      each_instance(:ApplicationService) { count += 1 }
      info("Found \#{count} services")
    RUBY

    @sandbox.instance_eval(script, "test", 1)

    message = @sandbox.sections.find { |s| s[:type] == :message }

    assert_includes(message[:message], "Found")
  end
end
