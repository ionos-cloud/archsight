# frozen_string_literal: true

require "uri"
require "time"

# Page is a wiki page authored as a markdown file with YAML frontmatter.
# It is sourced by Archsight::PageLoader and arranged in a tree by PageMenu.
class Archsight::Resources::Page < Archsight::Resources::Base
  description <<~MD
    Represents a wiki page authored as a markdown file with YAML frontmatter.

    ## Definition

    A Page is a tool-specific resource type. Unlike other resources it is not defined in YAML but in a
    `.md` file whose leading `---` block carries the metadata. The markdown body may contain tables,
    `asd` diagrams and `[[links]]` to other pages and resources. Pages are arranged in the sidebar
    tree by PageMenu resources.

    ## Frontmatter

    `title`, `author`, `owner`, `status`, `tags` (comma-separated), `toc` (yes/no), `confluence`
    (URL of the linked Confluence page) and an optional `name` (defaults to the file path).
  MD

  icon "page"
  layer "other"

  annotation "page/title",
             description: "Page title shown in the page tree and header",
             title: "Title",
             sidebar: false
  annotation "page/author",
             description: "Author of the page (Name <email@domain.com>, or just a name)",
             title: "Author",
             type: Archsight::Annotations::Person,
             sidebar: false
  annotation "page/owner",
             description: "Owner responsible for keeping the page up to date (Name <email@domain.com>, or just a name)",
             title: "Owner",
             type: Archsight::Annotations::Person,
             sidebar: false,
             summary: true
  annotation "page/status",
             description: "Lifecycle status (e.g. rfc, wip, approved)",
             filter: :word,
             title: "Status",
             summary: true
  annotation "page/tags",
             description: "Comma-separated tags",
             filter: :list,
             title: "Tags"
  annotation "page/toc",
             description: "Show a table of contents (yes/no)",
             title: "Table of Contents",
             enum: %w[yes no],
             sidebar: false
  annotation "page/confluence",
             description: "URL of the corresponding Confluence page (used for a later export)",
             title: "Confluence",
             type: URI,
             sidebar: false
  annotation "page/created",
             description: "When the page was created (ISO 8601 date or time)",
             title: "Created",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) },
             sidebar: false
  annotation "page/updated",
             description: "When the page was last changed (ISO 8601 date or time)",
             title: "Updated",
             validator: ->(value) { Archsight::Resources::Page.timestamp_error(value) },
             sidebar: false
  annotation "page/properties",
             description: "Further properties of the page, one `Key: value` per line (frontmatter: a mapping)",
             title: "Properties",
             format: :multiline,
             sidebar: false
  annotation "page/content",
             description: "Markdown body of the page",
             title: "Content",
             format: :markdown,
             sidebar: false

  # Validator of the timestamp annotations: nil for an ISO 8601 date or time, else the message
  def self.timestamp_error(value)
    text = value.to_s
    return nil if text.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Time.iso8601(text)
    nil
  rescue ArgumentError
    "expected an ISO 8601 date or time, e.g. 2026-10-02 or 2026-10-02T09:30:00Z"
  end

  # The `Key: value` lines of `page/properties`, in order
  # @return [Array<Array(String, String)>]
  def properties
    annotations["page/properties"].to_s.lines.filter_map do |line|
      key, value = line.chomp.split(/:\s*/, 2)
      [key.strip, value.to_s.strip] unless key.to_s.strip.empty?
    end
  end

  # Title to display, falls back to the resource name
  def title
    annotations["page/title"] || name
  end

  # The start page: shown at `/` instead of the generated overview, so it needs no menu.
  # A page is the home page when its name or its title is "Home" (any case).
  def home?
    [name, title].any? { |value| value.to_s.casecmp?("home") }
  end
end
