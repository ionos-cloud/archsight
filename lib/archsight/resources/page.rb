# frozen_string_literal: true

require "uri"

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
             description: "Author of the page (Name <email@domain.com>)",
             title: "Author",
             type: Archsight::Annotations::EmailRecipient,
             sidebar: false
  annotation "page/owner",
             description: "Owner responsible for keeping the page up to date (Name <email@domain.com>)",
             title: "Owner",
             type: Archsight::Annotations::EmailRecipient,
             sidebar: false
  annotation "page/status",
             description: "Lifecycle status (e.g. rfc, wip, approved)",
             filter: :word,
             title: "Status"
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
  annotation "page/content",
             description: "Markdown body of the page",
             title: "Content",
             format: :markdown,
             sidebar: false

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
