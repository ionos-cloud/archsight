# frozen_string_literal: true

require_relative "../../test_helper"
require "tmpdir"
require "fileutils"
require "archsight/database"
require "archsight/helpers"

class ChildrenMacroTest < Minitest::Test
  Macros = Archsight::Helpers::Macros

  MENUS = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: PageMenu
    metadata:
      name: Top
    spec:
      opens:
        pages: [top]
      contains:
        pages: [b-page, a-page]
        menus: [Inner]
    ---
    apiVersion: architecture/v1alpha1
    kind: PageMenu
    metadata:
      name: Inner
    spec:
      opens:
        pages: [inner]
      contains:
        pages: [deep]
  YAML

  def setup
    @dir = Dir.mktmpdir
    { "top" => "Top", "b-page" => "B <page>", "a-page" => "A page", "inner" => "Inner page", "deep" => "Deep" }.each do |name, title|
      File.write(File.join(@dir, "#{name}.md"), "---\ntitle: \"#{title}\"\n---\nx\n")
    end
    File.write(File.join(@dir, "menus.yaml"), MENUS)
    @db = Archsight::Database.new(@dir, compute_annotations: false).tap(&:reload!)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def context(name) = Macros::Context.new(@db, @db.instance_by_kind("Page", name))

  def render(html, page = "top") = Macros.render(html, context: context(page))

  def test_lists_the_child_pages_and_sub_menus_with_escaped_titles
    html = render("<p>{children}</p>")

    assert_equal %(<ul class="macro-children macro-block"><li><a href="/pages/b-page">B &lt;page&gt;</a></li><li><a href="/pages/a-page">A page</a></li><li><a href="/pages/inner">Inner</a></li></ul>), html
  end

  def test_options_deepen_sort_and_reverse
    deep = render("{children:depth=2}")

    assert_includes deep, %(<li><a href="/pages/inner">Inner</a><ul><li><a href="/pages/deep">Deep</a></li></ul></li>)
    assert_equal deep, render("{children:all}")
    assert_operator render("{children:sort=title}").index("A page"), :<, render("{children:sort=title}").index("B &lt;page&gt;")
    assert_operator render("{children:reverse}").index("Inner"), :<, render("{children:reverse}").index("A page")
  end

  def test_a_page_no_menu_opens_says_it_has_no_children
    assert_equal %(<div class="macro-children-empty macro-block">No child pages</div>), render("<p>{children}</p>", "a-page")
  end

  def test_without_a_page_the_macro_stays_as_written
    assert_equal "<p>{children}</p>", Macros.render("<p>{children}</p>")
  end

  def test_bad_options_and_ordinary_braces_stay_as_written
    ["{children:depth=0}", "{children:depth=x}", "{children:sideways}", "{children:all=yes}", "{childs}", "{}"].each do |text|
      assert_equal text, render(text), text
    end
    assert_equal ["{children:sideways}: expected options from: depth=N, all, sort=title, reverse"], Macros.problems("{children:sideways} {children} {children:all}")
  end

  def test_code_is_left_alone
    assert_equal "<code>{children}</code>", render("<code>{children}</code>")
  end

  def test_confluence_children_macro
    xml = ->(text) { Macros.replace(text) { |m, v| m.confluence(v) } }

    assert_equal %(<ac:structured-macro ac:name="children"></ac:structured-macro>), xml.call("{children}")
    params = %(<ac:parameter ac:name="all">true</ac:parameter><ac:parameter ac:name="sort">title</ac:parameter><ac:parameter ac:name="reverse">true</ac:parameter>)

    assert_equal %(<ac:structured-macro ac:name="children">#{params}</ac:structured-macro>), xml.call("{children:all sort=title reverse}")
    assert_includes xml.call("{children:depth=3}"), %(<ac:parameter ac:name="depth">3</ac:parameter>)
  end

  def test_pagetree_shows_the_page_with_all_its_descendants
    html = render("<p>{pagetree}</p>")

    root = %(<li><a href="/pages/top">Top</a>)
    leaves = %(<li><a href="/pages/b-page">B &lt;page&gt;</a></li><li><a href="/pages/a-page">A page</a></li>)
    inner = %(<li><a href="/pages/inner">Inner</a><ul><li><a href="/pages/deep">Deep</a></li></ul></li>)

    assert_equal %(<ul class="macro-children macro-pagetree macro-block">#{root}<ul>#{leaves}#{inner}</ul></li></ul>), html
  end

  def test_pagetree_can_start_elsewhere_and_sort
    html = render("{pagetree:root=inner}")

    assert_includes html, %(<li><a href="/pages/inner">Inner page</a><ul><li><a href="/pages/deep">Deep</a></li></ul></li>)
    refute_includes html, "/pages/top"
    assert_operator render("{pagetree:sort=title}").index("A page"), :<, render("{pagetree:sort=title}").index("B &lt;page&gt;")
  end

  def test_pagetree_of_a_page_without_children_is_just_that_page
    assert_equal %(<ul class="macro-children macro-pagetree macro-block"><li><a href="/pages/a-page">A page</a></li></ul>), render("{pagetree}", "a-page")
  end

  def test_pagetree_with_bad_options_or_no_page_stays_as_written_and_the_linter_names_the_problem
    assert_equal "{pagetree:depth=2}", render("{pagetree:depth=2}")
    assert_equal "{pagetree:root=missing}", render("{pagetree:root=missing}")
    assert_equal "{pagetree}", Macros.render("{pagetree}")
    assert_equal ["{pagetree:root=missing}: there is no page named \"missing\""], Macros.problems("{pagetree:root=missing} {pagetree}", context: context("top"))
    assert_equal ["{pagetree:depth=2}: expected options from: root=PAGE, sort=title, reverse"], Macros.problems("{pagetree:depth=2}")
  end

  def test_confluence_pagetree_macro
    xml = ->(text) { Macros.replace(text) { |m, v| m.confluence(v, context("top")) } }

    assert_equal %(<ac:structured-macro ac:name="pagetree"><ac:parameter ac:name="root">@self</ac:parameter></ac:structured-macro>), xml.call("{pagetree}")
    assert_includes xml.call("{pagetree:root=inner sort=title reverse}"),
                    %(<ac:parameter ac:name="root">Inner page</ac:parameter><ac:parameter ac:name="sort">title</ac:parameter><ac:parameter ac:name="reverse">true</ac:parameter>)
  end
end
