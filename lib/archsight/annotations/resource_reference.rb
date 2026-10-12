# frozen_string_literal: true

# A reference to another resource: `Name` (a resource of the same kind as the annotated one) or `Kind/Name` for
# another kind (names contain `:`, so `/` separates the kind). The format is checked when the annotation is
# validated; whether the resource exists is checked by the linter, which has the database.
class Archsight::Annotations::ResourceReference
  FORMAT = %r{\A(?:[A-Za-z][A-Za-z0-9]*/)?[^\s/]+\z}

  def self.valid?(value)
    value.to_s.strip.match?(FORMAT)
  end
end
