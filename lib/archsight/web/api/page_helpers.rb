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

  # The filters of the pages sidebar: every Page annotation that has a `filter` and is not `sidebar: false`
  # (the same rule as the filters of the Kinds sidebar), each with its values and the number of pages using them
  def page_filters
    pages = db.instances_by_kind("Page").values
    Archsight::Resources::Page.filterable_annotations.filter_map do |annotation|
      counts = pages.flat_map { |page| Array(annotation.value_for(page)) }.compact.tally
      next if counts.empty?

      { key: annotation.key, title: annotation.title, filter_type: annotation.filter.to_s,
        values: counts.sort.map { |value, count| { value: value, count: count } } }
    end
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
      created: annotations["page/created"],
      updated: annotations["page/updated"],
      properties: page.properties.map { |key, value| { key: key, value: value, html: inline_markdown(value, page) } },
      confluence: annotations["page/confluence"],
      tags: Archsight::Resources::Page.annotation_matching("page/tags")&.value_for(page) || [],
      toc: annotations["page/toc"] == "yes" ? Archsight::PageTree.toc(body) : [],
      breadcrumb: tree.breadcrumb(page),
      html: markdown(body, base: Archsight::Assets.base_dir_for(page, resources_dir: Archsight.resources_dir), page: page),
      backlinks: page_backlinks(page)
    }
  end

  # A short text (a page property) rendered as inline markdown: links, emphasis, `{macros}`, [[wiki links]], without the
  # paragraph around it
  def inline_markdown(text, page)
    html = markdown(text.to_s, base: Archsight::Assets.base_dir_for(page, resources_dir: Archsight.resources_dir), page: page)
    html.strip.sub(%r{\A<p>(.*)</p>\z}m, '\1')
  end

  # The header already shows the title, so a leading "# Title" that repeats it is dropped
  # (Confluence exports and hand-written pages usually start with one).
  def strip_duplicate_title(body, page)
    first, rest = body.lstrip.split("\n", 2)
    heading = first.to_s[/\A#\s+(.+?)\s*#*\s*\z/, 1]
    return body unless heading && [page.title, page.name].any? { |t| t.to_s.casecmp?(heading) }

    rest.to_s.lstrip
  end

  # The other pages that link to this page with [[name]] or [[title]] (optionally with |label): the pages that mention it
  # (see Archsight::References), so a link in code does not count and a page is not listed twice.
  def page_backlinks(page)
    page.references
        .select { |ref| ref[:verb] == :mentions && ref[:instance].klass == "Page" && !ref[:instance].equal?(page) }
        .map { |ref| ref[:instance] }
        .uniq
        .sort_by(&:name)
        .map { |other| { name: other.name, title: other.title } }
  end
end
