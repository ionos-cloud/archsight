# frozen_string_literal: true

require_relative "email_recipient"

# Annotation represents a single annotation definition with its schema and behavior
class Archsight::Annotations::Annotation
  attr_reader :key, :description, :filter, :format, :enum, :sidebar, :type, :list

  def initialize(key, options = {})
    @key = key
    @description = options[:description]
    @explicit_title = options[:title]
    @filter = options[:filter]
    @enum = options[:enum]
    @sidebar = options.fetch(:sidebar, true)
    @list = options.fetch(:list, false)
    @type = options[:type]

    # Auto-add filter if enum present
    @filter ||= :word if @enum

    # Derive format from filter if not explicitly set
    @format = options[:format] || derive_format

    # Build regex for pattern annotations
    @regex = build_regex if pattern?
  end

  # === Schema Methods ===

  def pattern?
    key.include?("*")
  end

  def matches?(test_key)
    pattern? ? @regex.match?(test_key) : key == test_key
  end

  def title
    @explicit_title || key.split("/").last.capitalize
  end

  def filterable?
    @filter && @sidebar != false
  end

  def list?
    @filter == :list
  end

  def list_display?
    @list == true
  end

  def has_validation?
    @enum || @type.is_a?(Class)
  end

  # === Value Methods (for instance values) ===

  # Get value(s) from instance
  # Returns array for list annotations, coerced single value otherwise
  def value_for(instance)
    raw = instance.annotations[key]

    if list?
      return [] if raw.nil? || raw.to_s.empty?

      raw.to_s.split(/,|\n/).map(&:strip).reject(&:empty?)
    else
      return nil if raw.nil?

      case @type
      when Integer then raw.to_i
      when Float then raw.to_f
      else raw
      end
    end
  end

  # Validate a value and return array of error messages (empty if valid)
  def validate(value)
    errors = []
    return errors if value.nil?

    validate_enum(value, errors)
    validate_type(value, errors) if errors.empty?
    validate_code(value, errors) if errors.empty?

    errors
  end

  # Check if value is valid (convenience method)
  def valid?(value)
    validate(value).empty?
  end

  def markdown?
    @format == :markdown
  end

  def code?
    @format == :ruby
  end

  def code_language
    @format if code?
  end

  # Example value for templates
  def example_value
    if @enum
      @enum.first || "TODO"
    elsif @type == Float
      0.0
    elsif @type == Integer
      0
    else
      "TODO"
    end
  end

  private

  def type_error_message
    case @type.to_s
    when "URI" then "Expected valid HTTP/HTTPS URL"
    when "Integer" then "Expected an integer value"
    when "Float" then "Expected a float value"
    when "Archsight::Annotations::EmailRecipient" then 'Expected email format: "Name <email@domain.com>" or "email@domain.com"'
    else "Invalid value for type #{@type}"
    end
  end

  def validate_enum(value, errors)
    return unless @enum

    values = list? ? value.to_s.split(",").map(&:strip) : [value.to_s]
    invalid_values = values.reject { |v| @enum.include?(v) }
    invalid_values.each do |v|
      errors << "invalid value '#{v}'. Expected one of: #{@enum.join(", ")}"
    end
  end

  def validate_type(value, errors)
    return unless @type.is_a?(Class)

    values_to_check = list? ? value.to_s.split(/,|\n/).map(&:strip).reject(&:empty?) : [value.to_s]
    values_to_check.each do |string_value|
      errors << "invalid value '#{string_value}'. #{type_error_message}" unless valid_type_value?(string_value)
    end
  end

  def valid_type_value?(string_value)
    case @type.to_s
    when "Integer" then string_value.match?(/\A-?\d+\z/)
    when "Float" then string_value.match?(/\A-?\d+(\.\d+)?\z/)
    when "URI" then valid_uri?(string_value)
    when "Archsight::Annotations::EmailRecipient" then Archsight::Annotations::EmailRecipient.valid?(string_value)
    else true
    end
  end

  def valid_uri?(string_value)
    URI.parse(string_value)
    string_value.match?(%r{\Ahttps?://})
  rescue URI::InvalidURIError
    false
  end

  def validate_code(value, errors)
    return unless code? && !value.to_s.strip.empty?

    syntax_error = validate_code_syntax(value.to_s)
    errors << syntax_error if syntax_error
  end

  def derive_format
    case @filter
    when :word then :tag_word
    when :list then :tag_list
    end
  end

  def build_regex
    Regexp.new("^#{Regexp.escape(key).gsub('\*', ".+")}$")
  end

  # Validate code syntax based on format
  # @param code [String] The code to validate
  # @return [String, nil] Error message or nil if valid
  def validate_code_syntax(code)
    case @format
    when :ruby
      validate_ruby_syntax(code)
    end
  end

  # Validate Ruby syntax using RubyVM
  # @param code [String] Ruby code to validate
  # @return [String, nil] Error message or nil if valid
  def validate_ruby_syntax(code)
    # steep:ignore:start
    RubyVM::InstructionSequence.compile(code)
    # steep:ignore:end
    nil
  rescue SyntaxError => e
    # Extract just the error message without the full backtrace
    message = e.message.lines.first&.strip || "Syntax error"
    "Ruby syntax error: #{message}"
  end
end
