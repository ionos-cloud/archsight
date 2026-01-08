# frozen_string_literal: true

require "test_helper"

class TestArchsight < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Archsight::VERSION
  end

  def test_resources_are_registered
    # Verify core resource types are registered
    assert Archsight::Resources["TechnologyArtifact"]
    assert Archsight::Resources["ApplicationComponent"]
    assert Archsight::Resources["ApplicationInterface"]
  end
end
