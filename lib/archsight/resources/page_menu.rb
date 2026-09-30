# frozen_string_literal: true

# PageMenu groups pages and other menus into the page tree shown in the sidebar.
class Archsight::Resources::PageMenu < Archsight::Resources::Base
  description <<~MD
    Groups pages and sub-menus into the page tree shown in the sidebar.

    ## Definition

    A PageMenu lists its children explicitly in `spec.contains`. The order of the list is the display
    order. A menu that is not contained in another menu is a root of the tree.
  MD

  icon "folder"
  layer "other"

  relation :contains, :pages, "Page"
  relation :contains, :menus, "PageMenu"

  annotation "menu/title",
             description: "Title shown in the page tree",
             title: "Title",
             sidebar: false
  annotation "menu/icon",
             description: "Optional iconoir icon name",
             title: "Icon",
             sidebar: false

  def title
    annotations["menu/title"] || name
  end
end
