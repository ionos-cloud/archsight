# frozen_string_literal: true

require "test_helper"
require "archsight/export/confluence/page_url"

class ConfluencePageUrlTest < Minitest::Test
  PageUrl = Archsight::Export::Confluence::PageUrl

  def test_spaces_url_with_page_id
    url = PageUrl.parse("https://wiki.example.com/spaces/~someone/pages/12345/Test")

    assert_equal "https://wiki.example.com", url.base
    assert_equal "12345", url.page_id
    assert_equal "~someone", url.space
    assert_equal "https://wiki.example.com/pages/viewpage.action?pageId=12345", url.view_url
  end

  def test_context_path_and_port_are_part_of_the_base
    assert_equal "https://wiki.example.com:8443/confluence", PageUrl.parse("https://wiki.example.com:8443/confluence/spaces/ARCH/pages/42/X").base
  end

  def test_viewpage_action
    url = PageUrl.parse("https://wiki.example.com/confluence/pages/viewpage.action?pageId=77")

    assert_equal ["https://wiki.example.com/confluence", "77"], [url.base, url.page_id]
  end

  def test_display_url_has_space_and_title_but_no_id
    url = PageUrl.parse("https://wiki.example.com/display/ARCH/My+Page")

    assert_nil url.page_id
    assert_equal ["ARCH", "My Page"], [url.space, url.title]
  end

  def test_unusable_urls_are_rejected
    ["", "not a url", "ftp://x/spaces/A/pages/1", "https://wiki.example.com/x/AbCd", "https://wiki.example.com/pages/viewpage.action?pageId=abc"].each do |bad|
      assert_raises(ArgumentError, bad) { PageUrl.parse(bad) }
    end
  end
end
