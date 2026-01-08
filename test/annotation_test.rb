# frozen_string_literal: true

require_relative "test_helper"
require "archsight/annotations/annotation"
require "archsight/resources"

class EmailRecipientTest < Minitest::Test
  def test_valid_email_only
    assert Archsight::Annotations::EmailRecipient.valid?("test@example.com")
    assert Archsight::Annotations::EmailRecipient.valid?("user.name@domain.org")
    assert Archsight::Annotations::EmailRecipient.valid?("user+tag@sub.domain.co.uk")
  end

  def test_valid_recipient_format
    assert Archsight::Annotations::EmailRecipient.valid?("John Doe <john@example.com>")
    assert Archsight::Annotations::EmailRecipient.valid?("Jane Smith <jane.smith@example.com>")
    assert Archsight::Annotations::EmailRecipient.valid?("Dr. Jane Smith <jane.smith@company.org>")
  end

  def test_invalid_name_only
    refute Archsight::Annotations::EmailRecipient.valid?("John Doe")
    refute Archsight::Annotations::EmailRecipient.valid?("Stephan Reiche")
    refute Archsight::Annotations::EmailRecipient.valid?("Alexander Lindhorst")
  end

  def test_invalid_empty
    refute Archsight::Annotations::EmailRecipient.valid?(nil)
    refute Archsight::Annotations::EmailRecipient.valid?("")
    refute Archsight::Annotations::EmailRecipient.valid?("   ")
  end

  def test_invalid_malformed_email
    refute Archsight::Annotations::EmailRecipient.valid?("notanemail")
    refute Archsight::Annotations::EmailRecipient.valid?("@missing.local")
    refute Archsight::Annotations::EmailRecipient.valid?("missing@domain")
  end

  def test_invalid_malformed_recipient
    refute Archsight::Annotations::EmailRecipient.valid?("Name <notanemail>")
    refute Archsight::Annotations::EmailRecipient.valid?("Name <>")
    refute Archsight::Annotations::EmailRecipient.valid?("<email@example.com>")
  end

  def test_extract_email_from_recipient
    assert_equal "john@example.com", Archsight::Annotations::EmailRecipient.extract_email("John Doe <john@example.com>")
    assert_equal "jane.smith@example.com",
                 Archsight::Annotations::EmailRecipient.extract_email("Jane Smith <jane.smith@example.com>")
  end

  def test_extract_email_direct
    assert_equal "test@example.com", Archsight::Annotations::EmailRecipient.extract_email("test@example.com")
  end

  def test_extract_email_invalid
    assert_nil Archsight::Annotations::EmailRecipient.extract_email("John Doe")
    assert_nil Archsight::Annotations::EmailRecipient.extract_email(nil)
  end
end

class AnnotationEmailRecipientValidationTest < Minitest::Test
  def setup
    @annotation = Archsight::Annotations::Annotation.new("team/lead", type: Archsight::Annotations::EmailRecipient)
    @list_annotation = Archsight::Annotations::Annotation.new("team/members",
                                                              type: Archsight::Annotations::EmailRecipient, filter: :list)
  end

  def test_validates_single_email
    assert_empty @annotation.validate("test@example.com")
    assert_empty @annotation.validate("John Doe <john@example.com>")
  end

  def test_rejects_name_only
    errors = @annotation.validate("John Doe")

    refute_empty errors
    assert_match(/Expected email format/, errors.first)
  end

  def test_validates_list_of_emails
    assert_empty @list_annotation.validate("john@example.com, jane@example.com")
    assert_empty @list_annotation.validate("John Doe <john@example.com>, Jane Doe <jane@example.com>")
  end

  def test_rejects_list_with_invalid_entry
    errors = @list_annotation.validate("john@example.com, Invalid Name")

    refute_empty errors
    assert_match(/Invalid Name/, errors.first)
  end
end

class IncludeAnnotationsTest < Minitest::Test
  def test_include_annotations_valid_symbol
    # Create a test class that uses include_annotations
    test_class = Class.new(Archsight::Resources::Base) do
      include_annotations :git
    end

    # Should have git annotations defined
    assert(test_class.annotations.any? { |a| a.key.start_with?("git/") })
  end

  def test_include_annotations_multiple_symbols
    test_class = Class.new(Archsight::Resources::Base) do
      include_annotations :git, :architecture
    end

    # Should have both git and architecture annotations
    assert(test_class.annotations.any? { |a| a.key.start_with?("git/") })
    assert(test_class.annotations.any? { |a| a.key.start_with?("architecture/") })
  end

  def test_include_annotations_all_modules
    test_class = Class.new(Archsight::Resources::Base) do
      include_annotations :git, :architecture, :backup, :generated
    end

    # Should have all annotation types
    assert(test_class.annotations.any? { |a| a.key.start_with?("git/") })
    assert(test_class.annotations.any? { |a| a.key.start_with?("architecture/") })
    assert(test_class.annotations.any? { |a| a.key.start_with?("backup/") })
    assert(test_class.annotations.any? { |a| a.key.start_with?("generated/") })
  end

  def test_include_annotations_invalid_raises_error
    error = assert_raises(RuntimeError) do
      Class.new(Archsight::Resources::Base) do
        include_annotations :invalid_module
      end
    end

    assert_match(/Unknown annotation module :invalid_module/, error.message)
    assert_match(/:git/, error.message)
    assert_match(/:architecture/, error.message)
    assert_match(/:backup/, error.message)
    assert_match(/:generated/, error.message)
  end

  def test_include_annotations_partial_invalid_raises_error
    error = assert_raises(RuntimeError) do
      Class.new(Archsight::Resources::Base) do
        include_annotations :git, :nonexistent
      end
    end

    assert_match(/Unknown annotation module :nonexistent/, error.message)
  end
end
