# frozen_string_literal: true

# Links module adds the links of a resource to other systems: `link/<name>` holds a URL, the name says which
# (confluence, jira, github, ...). A link has no direction; it can be where the resource comes from or where it
# was published to.
module Archsight::Annotations::Links
  def self.included(base)
    base.class_eval do
      annotation "link/*",
                 description: "Links to the resource in other systems and to related documents (name and URL)",
                 sidebar: false,
                 validator: ->(value) { "'#{value}' is not an http(s) URL" unless value.match?(%r{\Ahttps?://\S+\z}) }
    end
  end
end
