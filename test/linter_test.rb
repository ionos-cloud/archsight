# frozen_string_literal: true

require "test_helper"

class LinterTest < Minitest::Test
  def setup
    @resources_dir = File.expand_path("../examples/archsight", __dir__)
    @db = Archsight::Database.new(@resources_dir, verbose: false, compute_annotations: false)
    @db.reload!
  end

  def test_validate_returns_array
    linter = Archsight::Linter.new(@db)
    errors = linter.validate

    assert_kind_of Array, errors
  end

  def test_validate_example_resources_are_valid
    linter = Archsight::Linter.new(@db)
    errors = linter.validate

    assert_empty errors, "Example resources should have no validation errors: #{errors.join(", ")}"
  end

  def test_valid_components_constant
    expected = %w[activity git jira languages owner repositories status]

    assert_equal expected, Archsight::Linter::VALID_COMPONENTS
  end

  # Test unknown annotation detection
  def test_validate_unknown_annotation
    # Create a mock instance that returns nil for all annotations
    mock_instance = MockInstance.new("Test", { "unknown/annotation" => "value" }, return_nil_for_all: true)
    mock_db = create_mock_db({ "Test" => { "test" => mock_instance } })

    linter = Archsight::Linter.new(mock_db)
    errors = linter.validate

    assert_equal 1, errors.length
    assert_includes errors.first, "Unknown annotation 'unknown/annotation'"
  end

  # Test view field validation with invalid component
  def test_validate_view_invalid_component
    mock_instance = create_mock_instance("View", { "view/fields" => "@invalid_component" })
    mock_db = create_mock_db({ "View" => { "test_view" => mock_instance } })

    linter = Archsight::Linter.new(mock_db)
    errors = linter.validate

    assert_equal 1, errors.length
    assert_includes errors.first, "Unknown view component '@invalid_component'"
    assert_includes errors.first, "Valid components:"
  end

  # Test view field validation skips non-@ fields
  def test_validate_view_skips_non_component_fields
    mock_instance = create_mock_instance("View", { "view/fields" => "name, status, @activity" })
    mock_db = create_mock_db({ "View" => { "test_view" => mock_instance } })

    linter = Archsight::Linter.new(mock_db)
    errors = linter.validate

    # Should not error - 'name' and 'status' are not components (no @ prefix)
    # '@activity' is a valid component
    assert_empty errors
  end

  # Test view field validation with multiple invalid components
  def test_validate_view_multiple_invalid_components
    mock_instance = create_mock_instance("View", { "view/fields" => "@bad1, @bad2, @activity" })
    mock_db = create_mock_db({ "View" => { "test_view" => mock_instance } })

    linter = Archsight::Linter.new(mock_db)
    errors = linter.validate

    assert_equal 2, errors.length
    assert(errors.any? { |e| e.include?("@bad1") })
    assert(errors.any? { |e| e.include?("@bad2") })
  end

  # Test view field validation with nil fields
  def test_validate_view_nil_fields
    mock_instance = create_mock_instance("View", {})
    mock_db = create_mock_db({ "View" => { "test_view" => mock_instance } })

    linter = Archsight::Linter.new(mock_db)
    errors = linter.validate

    assert_empty errors
  end

  def test_validate_markdown_reports_a_broken_asd_block
    good = "```asd\ncomponent \"a\" { label \"A\" }\n```\n"
    bad = "intro\n\n```asd\nnot valid ((\n```\n"

    assert_empty lint("architecture/description" => good)
    errors = lint("architecture/description" => bad)

    assert_equal 1, errors.length
    assert_includes errors.first, "Diagram error in annotation 'architecture/description' (asd block 1)"
  end

  def test_validate_diagram_annotation
    assert_empty lint("architecture/diagram" => "component \"a\" { label \"A\" }\n")

    errors = lint("architecture/diagram" => "not valid ((\n")

    assert_equal 1, errors.length
    assert_includes errors.first, "Diagram error in annotation 'architecture/diagram':"
  end

  def test_validate_reports_diagram_resource_links_that_do_not_resolve
    source = %(component "a" { resource "Nope" }\ncomponent "b" { resource "Dup" }\n)
    errors = lint("architecture/diagram" => source)

    assert_equal 2, errors.length
    assert_includes errors.first, %(Diagram resource link "Nope" not found in annotation 'architecture/diagram' (node "a", line 1))
    assert_includes errors.last, %(Diagram resource link "Dup" is ambiguous, use Kind/Name)
  end

  def test_validate_reports_resource_links_in_markdown_asd_blocks
    errors = lint("architecture/description" => "x\n\n```asd\ncomponent \"a\" { resource \"Nope\" }\n```\n")

    assert_equal 1, errors.length
    assert_includes errors.first, "in annotation 'architecture/description' (asd block 1) (node \"a\", line 1)"
  end

  def test_validate_accepts_resource_links_that_resolve
    assert_empty lint("architecture/diagram" => %(component "a" { resource "Test:Exists" }\n))
  end

  def test_validate_diagram_annotation_skips_generated_resources
    assert_empty lint("architecture/diagram" => "not valid ((\n", "generated/script" => "x")
  end

  private

  def lint(annotations)
    formats = { "architecture/description" => :markdown, "architecture/diagram" => :asd, "generated/script" => nil }
    instance = MockInstance.new("Test", annotations, formats: formats)
    other = ->(kind) { MockInstance.new(kind, {}) }
    # "Test:Exists" resolves to one resource, "Dup" exists in two kinds
    instances = { "Test" => { "test" => instance, "Test:Exists" => other.call("Test") },
                  "Other" => { "Dup" => other.call("Other") }, "Third" => { "Dup" => other.call("Third") } }
    Archsight::Linter.new(create_mock_db(instances)).validate
  end

  def create_mock_instance(klass, annotations)
    MockInstance.new(klass, annotations)
  end

  def create_mock_db(instances)
    MockDatabase.new(instances)
  end

  # Mock instance for testing
  class MockInstance
    attr_reader :klass, :annotations

    # Known annotations that should not trigger "unknown" errors
    KNOWN_ANNOTATIONS = %w[view/fields].freeze

    def initialize(klass, annotations, return_nil_for_all: false, formats: {})
      @klass = klass
      @annotations = annotations
      @return_nil_for_all = return_nil_for_all
      @formats = formats
    end

    def path_ref
      "test/mock.yaml:1"
    end

    def class
      self
    end

    def annotation_matching(key)
      return nil if @return_nil_for_all
      return MockAnnotation.new(@formats[key]) if @formats.key?(key)
      return MockAnnotation.new if KNOWN_ANNOTATIONS.include?(key)

      nil
    end
  end

  # Mock annotation that has no validation
  class MockAnnotation
    def initialize(format = nil)
      @format = format
    end

    def has_validation?
      false
    end

    def markdown?
      @format == :markdown
    end

    def diagram?
      @format == :asd
    end
  end

  # Mock database for testing
  class MockDatabase
    def initialize(instances)
      @instances = instances
    end

    attr_reader :instances
  end
end
