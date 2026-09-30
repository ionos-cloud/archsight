# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

module Archsight
  # PageTree builds the sidebar tree, breadcrumbs and tables of contents for Page resources
  # from the PageMenu `contains` relations of a Database.
  class PageTree
    UNSORTED = { "type" => "menu", "name" => "unsorted", "title" => "Unsorted" }.freeze

    def initialize(db)
      @db = db
    end

    # Nested tree: roots are the menus that no other menu contains. Pages without a menu are
    # collected in a trailing "Unsorted" menu.
    def tree
      roots = menus.values.reject { |m| contained_menu?(m) }.sort_by(&:name)
      nodes = roots.map { |m| menu_node(m, [m.name]) }
      orphans = unsorted_pages
      nodes << UNSORTED.merge("type" => "menu", "children" => orphans.map { |p| page_node(p) }) if orphans.any?
      nodes
    end

    # Menu titles leading to the page, outermost first
    def breadcrumb(page)
      trail = [] #: Array[Hash[String, String]]
      seen = Set.new
      current = parent_menu(page)
      while current && seen.add?(current.name)
        trail.unshift({ "name" => current.name, "title" => current.title })
        current = parent_menu(current)
      end
      trail
    end

    # Pages that are not contained in any menu. The home page is not one of them: it is shown
    # at `/` and does not need a menu.
    def unsorted_pages
      pages.values.reject { |p| parent_menu(p) || p.home? }.sort_by { |p| p.title.to_s.downcase }
    end

    # The page shown at `/` instead of the overview: a page named "Home" wins over one that is
    # only titled "Home" (then by name), so the choice does not depend on load order.
    def home_page
      pages.values.select(&:home?).min_by { |p| [p.name.casecmp?("home") ? 0 : 1, p.name] }
    end

    # Flat table of contents [{level:, id:, text:}] of a markdown body
    def self.toc(markdown)
      doc = Kramdown::Document.new(markdown.to_s, input: "GFM")
      entries = [] #: Array[Hash[String, untyped]]
      collect_toc(doc.to_toc, entries)
      entries
    end

    def self.collect_toc(root, entries)
      root.children.each do |item|
        header = item.value
        entries << { "level" => header.options[:level], "id" => header.attr["id"], "text" => header.options[:raw_text] }
        collect_toc(item, entries)
      end
    end

    private

    def menus
      @db.instances_by_kind("PageMenu")
    end

    def pages
      @db.instances_by_kind("Page")
    end

    def menu_node(menu, path)
      # pages first, then sub-menus, each in declaration order
      children = menu.relations(:contains, :pages) + menu.relations(:contains, :menus)
      {
        "type" => "menu",
        "name" => menu.name,
        "title" => menu.title,
        "icon" => menu.annotations["menu/icon"],
        "children" => children.filter_map { |child| child_node(child, path) }
      }
    end

    def child_node(child, path)
      case child
      when Archsight::Resources::PageMenu
        # guard against cycles
        path.include?(child.name) ? nil : menu_node(child, path + [child.name])
      when Archsight::Resources::Page
        page_node(child)
      end
    end

    def page_node(page)
      {
        "type" => "page",
        "name" => page.name,
        "title" => page.title
      }
    end

    def contained_menu?(menu)
      menu.references.any? { |r| r[:instance].is_a?(Archsight::Resources::PageMenu) }
    end

    def parent_menu(inst)
      ref = inst.references.find { |r| r[:instance].is_a?(Archsight::Resources::PageMenu) }
      ref && ref[:instance]
    end
  end
end
