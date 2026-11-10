# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "open3"
require "archsight/import/handlers/repository"
require "archsight/import/progress"

class RepositoryHandlerTest < Minitest::Test
  FakeImport = Struct.new(:raw, :name, :annotations, :path_ref)

  def setup
    @dir = Dir.mktmpdir
    @origin = File.join(@dir, "origin.git")
    @clone = File.join(@dir, "clone")
    @work = File.join(@dir, "work")
    git(@dir, "init", "--quiet", "--bare", "--initial-branch=main", @origin)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_unborn_local_head_follows_the_remote_default_branch_after_the_remote_gets_commits
    git(@dir, "clone", "--quiet", @origin, @clone)

    assert handler.send(:empty_repository?)

    push_commit

    handler.send(:update_repository)

    refute handler.send(:empty_repository?)
    assert_equal "hello", File.read(File.join(@clone, "README")).strip
  end

  def test_remote_that_is_still_empty_stays_empty
    git(@dir, "clone", "--quiet", @origin, @clone)

    handler.send(:update_repository)

    assert handler.send(:empty_repository?)
  end

  def test_born_clone_is_fast_forwarded_as_before
    push_commit
    git(@dir, "clone", "--quiet", @origin, @clone)
    push_commit("second")

    handler.send(:update_repository)

    assert_equal "second", File.read(File.join(@clone, "README")).strip
  end

  def test_git_service_comes_from_the_listing_import
    h = handler
    h.import_resource.annotations["import/config/gitService"] = "Git:Gitea"

    assert_equal "Git:Gitea", h.send(:git_service, "gitea@git.example.com:org/repo.git")
  end

  def test_git_service_falls_back_to_the_clone_url
    assert_equal "Git:Github", handler.send(:git_service, "git@github.com:org/repo.git")
    assert_equal "Git:Gitlab", handler.send(:git_service, "git@gitlab.example.com:org/repo.git")
  end

  private

  def push_commit(text = "hello")
    FileUtils.rm_rf(@work)
    git(@dir, "clone", "--quiet", @origin, @work)
    git(@work, "checkout", "--quiet", "-B", "main")
    File.write(File.join(@work, "README"), text)
    git(@work, "add", "README")
    git(@work, "-c", "user.name=t", "-c", "user.email=t@example.org", "commit", "--quiet", "-m", text)
    git(@work, "push", "--quiet", "origin", "main")
  end

  def git(dir, *args)
    out, err, status = Open3.capture3("git", *args, chdir: dir)
    raise "git #{args.join(" ")} failed: #{err}" unless status.success?

    out
  end

  def handler
    raw = { "metadata" => { "name" => "Import:Repository:test",
                            "annotations" => { "import/handler" => "repository", "import/config/path" => @clone } } }
    import = FakeImport.new(raw, raw.dig("metadata", "name"), raw.dig("metadata", "annotations"), Struct.new(:path).new("/tmp/x.yaml"))
    handler = Archsight::Import::Handlers::Repository.new(import, database: nil, resources_dir: @dir, progress: Archsight::Import::Progress.new(output: StringIO.new))
    handler.instance_variable_set(:@path, @clone)
    handler
  end
end
