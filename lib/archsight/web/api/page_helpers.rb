# frozen_string_literal: true

require_relative "../../page_tree"

module Archsight; end
module Archsight::Web; end
module Archsight::Web::API; end

# JSON serialization of wiki pages for the API
module Archsight::Web::API::PageHelpers
  # All page tags with the number of pages using them, sorted by tag
  def page_tag_counts
    annotation = Archsight::Resources::Page.annotation_matching("page/tags")
    counts = db.instances_by_kind("Page").values.flat_map { |page| annotation&.value_for(page) || [] }.tally
    counts.sort.map { |tag, count| { tag: tag, count: count } }
  end

  def build_page_response(page)
    annotations = page.annotations
    body = strip_duplicate_title(annotations["page/content"].to_s, page)
    tree = Archsight::PageTree.new(db)
    {
      name: page.name,
      title: page.title,
      status: annotations["page/status"],
      author: Archsight::Annotations::EmailRecipient.parse(annotations["page/author"]),
      owner: Archsight::Annotations::EmailRecipient.parse(annotations["page/owner"]),
      confluence: annotations["page/confluence"],
      tags: Archsight::Resources::Page.annotation_matching("page/tags")&.value_for(page) || [],
      toc: annotations["page/toc"] == "yes" ? Archsight::PageTree.toc(body) : [],
      breadcrumb: tree.breadcrumb(page),
      html: markdown(body, base: Archsight::Assets.base_dir_for(page, resources_dir: Archsight.resources_dir)),
      backlinks: page_backlinks(page)
    }
  end

  # The header already shows the title, so a leading "# Title" that repeats it is dropped
  # (Confluence exports and hand-written pages usually start with one).
  def strip_duplicate_title(body, page)
    first, rest = body.lstrip.split("\n", 2)
    heading = first.to_s[/\A#\s+(.+?)\s*#*\s*\z/, 1]
    return body unless heading && [page.title, page.name].any? { |t| t.to_s.casecmp?(heading) }

    rest.to_s.lstrip
  end

  # Other pages linking to this page with [[name]], [[title]] (optionally with |label)
  def page_backlinks(page)
    targets = [page.name, page.title].map { |t| Regexp.escape(t.to_s) }.uniq.join("|")
    pattern = /\[\[\s*(?:#{targets})\s*(?:\||\]\])/i
    db.instances_by_kind("Page").values
      .select { |other| other != page && other.annotations["page/content"].to_s.match?(pattern) }
      .sort_by(&:name)
      .map { |other| { name: other.name, title: other.title } }
  end
end
