# frozen_string_literal: true

# Custom type for email recipient validation
# Accepts: "Name <email@domain.com>" or "email@domain.com"
# Rejects: "Name" (no email)
class Archsight::Annotations::EmailRecipient
  # RFC 5322 simplified email pattern
  EMAIL_PATTERN = /\A[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\z/
  # Email recipient format: "Display Name <email@domain.com>"
  RECIPIENT_PATTERN = /\A.+\s+<([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>\z/

  def self.valid?(value)
    return false if value.nil? || value.to_s.strip.empty?

    str = value.to_s.strip
    # Check if it's a full recipient format "Name <email>"
    return true if str.match?(RECIPIENT_PATTERN)

    # Check if it's just an email address
    return true if str.match?(EMAIL_PATTERN)

    false
  end

  def self.extract_email(value)
    return nil if value.nil?

    str = value.to_s.strip
    if (match = str.match(RECIPIENT_PATTERN))
      match[1]
    elsif str.match?(EMAIL_PATTERN)
      str
    end
  end
end
