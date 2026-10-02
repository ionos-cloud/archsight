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
    # (the menu that opens the page is the page itself, so it is not part of its own trail)
    def breadcrumb(page)
      trail = [] #: Array[Hash[String, String]]
      seen = Set.new
      opener = opening_menu(page)
      current = parent_menu(page) || (opener && parent_menu(opener))
      while current && seen.add?(current.name)
        crumb = { "name" => current.name, "title" => current.title }
        crumb["page"] = current.own_page.name if current.own_page
        trail.unshift(crumb)
        current = parent_menu(current)
      end
      trail
    end

    # The child pages of a page: the contents of the menu that opens it. A sub-menu is one entry (its title, linked
    # to the page it opens), its own contents are the entries below it.
    # @param depth [Integer, Float] number of levels
    # @param sort [String, nil] "title" sorts every level by title, nil keeps the declared order
    # @return [Array<Hash>] `{ "name" => page name or nil, "title" =>, "children" => [...] }`
    def children(page, depth: 1, sort: nil, reverse: false)
      menu = opening_menu(page)
      menu ? child_entries(menu, depth, sort, reverse, [menu.name]) : []
    end

    # Pages that are not contained in any menu. The home page is not one of them: it is shown
    # at `/` and does not need a menu.
    def unsorted_pages
      pages.values.reject { |p| parent_menu(p) || opening_menu(p) || p.home? }.sort_by { |p| p.title.to_s.downcase }
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
        "page" => menu.own_page&.name,
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
      !parent_menu(menu).nil?
    end

    # The menu that contains a page or menu (opening a page does not make the menu its parent)
    def parent_menu(inst)
      ref = inst.references.find { |r| r[:instance].is_a?(Archsight::Resources::PageMenu) && r[:verb].to_s == "contains" }
      ref && ref[:instance]
    end

    # The menu whose title links to the page
    def opening_menu(page)
      ref = page.references.find { |r| r[:instance].is_a?(Archsight::Resources::PageMenu) && r[:verb].to_s == "opens" }
      ref && ref[:instance]
    end

    def child_entries(menu, depth, sort, reverse, path)
      entries = menu.relations(:contains, :pages).map { |page| { "name" => page.name, "title" => page.title, "children" => [] } }
      menu.relations(:contains, :menus).each do |sub|
        next if path.include?(sub.name)

        below = depth > 1 ? child_entries(sub, depth - 1, sort, reverse, path + [sub.name]) : []
        entries << { "name" => sub.own_page&.name, "title" => sub.title, "children" => below }
      end
      entries = entries.sort_by { |entry| entry["title"].to_s.downcase } if sort == "title"
      reverse ? entries.reverse : entries
    end
  end
end
