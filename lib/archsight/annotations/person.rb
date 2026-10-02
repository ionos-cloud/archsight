# frozen_string_literal: true

require_relative "email_recipient"

# A person: "Name <email@domain.com>", a bare email address or just a name.
# Pages use it for author and owner (Confluence often knows a name only).
class Archsight::Annotations::Person
  NAME = /\A[^<>@()\[\]{}\n]+\z/

  def self.valid?(value)
    string = value.to_s.strip
    Archsight::Annotations::EmailRecipient.valid?(string) || string.match?(NAME)
  end
end
