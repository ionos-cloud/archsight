# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "archsight/import"

class NeverIndexTest < Minitest::Test
  def setup
    @home = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@home)
  end

  def test_a_cache_root_below_the_archsight_cache_marks_the_archsight_cache
    home = Dir.home
    ENV["HOME"] = @home
    marker = Archsight::Import.never_index("~/.cache/archsight/git")

    assert_equal File.join(@home, ".cache/archsight/.metadata_never_index"), marker
    assert_path_exists marker
  ensure
    ENV["HOME"] = home
  end

  def test_a_cache_root_elsewhere_is_marked_itself
    root = File.join(@home, "clones")

    assert_equal File.join(root, ".metadata_never_index"), Archsight::Import.never_index(root)
    assert_path_exists File.join(root, ".metadata_never_index")
  end

  def test_an_existing_marker_is_kept
    marker = File.join(@home, ".metadata_never_index")
    File.write(marker, "kept")

    Archsight::Import.never_index(@home)

    assert_equal "kept", File.read(marker)
  end

  def test_a_directory_that_cannot_be_written_does_not_fail
    File.write(File.join(@home, "file"), "")

    assert_nil Archsight::Import.never_index(File.join(@home, "file", "below"))
  end
end
