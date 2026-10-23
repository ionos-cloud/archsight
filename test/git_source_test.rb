# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "open3"
require "archsight/git_source"

class GitSourceTest < Minitest::Test
  G = Archsight::GitSource

  def setup
    @dir = Dir.mktmpdir
    git("init", "-q", "-b", "main")
    FileUtils.mkdir_p(File.join(@dir, "arch/pages"))
    @file = File.join(@dir, "arch/pages/my page.md")
    File.write(@file, "---\ntitle: P\n---\n")
    git("add", ".")
    git("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-q", "-m", "init")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def git(*)
    _out, err, status = Open3.capture3("git", "-C", @dir, *)
    raise err unless status.success?
  end

  def test_a_github_file_links_to_its_blob_on_the_branch
    git("remote", "add", "origin", "git@github.com:example/architecture.git")
    location = G.locate(@file)

    assert_equal "example/architecture", location.repository
    assert_equal "https://github.com/example/architecture", location.repository_url
    assert_equal "arch/pages/my page.md", location.path
    assert_equal "https://github.com/example/architecture/blob/main/arch/pages/my%20page.md", location.url
  end

  def test_a_gitlab_file_links_to_its_blob
    git("remote", "add", "origin", "ssh://git@gitlab.example.com:2222/group/sub/architecture.git")

    assert_equal "https://gitlab.example.com/group/sub/architecture/-/blob/main/arch/pages/my%20page.md", G.locate(@file).url
  end

  def test_a_detached_head_links_to_the_commit
    git("remote", "add", "origin", "https://github.com/example/architecture")
    git("checkout", "-q", "--detach")
    sha, = Open3.capture2("git", "-C", @dir, "rev-parse", "HEAD")

    assert_includes G.locate(@file).url, "/blob/#{sha.strip}/"
  end

  def test_an_unknown_host_names_the_repository_without_a_file_link
    git("remote", "add", "origin", "https://git.example.com/example/architecture.git")
    location = G.locate(@file)

    assert_equal "https://git.example.com/example/architecture", location.repository_url
    assert_nil location.url
  end

  def test_an_untracked_file_has_no_file_link
    git("remote", "add", "origin", "git@github.com:example/architecture.git")
    draft = File.join(@dir, "arch/pages/draft.md")
    File.write(draft, "")

    assert_nil G.locate(draft).url
    assert_equal "https://github.com/example/architecture", G.locate(draft).repository_url
  end

  def test_no_remote_or_no_repository_is_no_location
    assert_nil G.locate(@file)

    outside = Dir.mktmpdir
    File.write(File.join(outside, "x.md"), "")

    assert_nil G.locate(File.join(outside, "x.md"))
  ensure
    FileUtils.rm_rf(outside) if outside
  end

  def test_credentials_of_the_remote_never_reach_the_link
    assert_equal ["github.com", "example/architecture"], G.host_and_repository("https://user:secret@github.com/example/architecture.git")
    assert_equal ["git.example.com:8443", "o/r"], G.host_and_repository("https://git.example.com:8443/o/r")
    assert_equal [nil, nil], G.host_and_repository("/srv/git/architecture.git")
  end
end
