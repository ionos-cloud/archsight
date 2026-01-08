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
end
