# frozen_string_literal: true

require_relative "../test_helper"
require "archsight/helpers"

class ResourceResolverTest < Minitest::Test
  Database = Struct.new(:instances)

  def setup
    service = Archsight::Resources["ApplicationService"]
    component = Archsight::Resources["ApplicationComponent"]
    db = Database.new({ service => { "Archsight:Web" => 1, "Dup" => 1, "With Space/x" => 1 }, component => { "Dup" => 1, "Only:Component" => 1 } })
    @resolver = Archsight::Helpers::ResourceResolver.new(db)
  end

  def test_a_bare_name_is_found_in_whichever_kind_has_it
    assert_equal "/kinds/ApplicationService/instances/Archsight:Web", @resolver.call("Archsight:Web")
    assert_equal "/kinds/ApplicationComponent/instances/Only:Component", @resolver.call("Only:Component")
  end

  def test_kind_and_name_pick_one_kind
    assert_equal "/kinds/ApplicationComponent/instances/Dup", @resolver.call("ApplicationComponent/Dup")
    assert_equal "/kinds/ApplicationService/instances/Archsight:Web", @resolver.call("ApplicationService/Archsight:Web")
  end

  def test_a_name_in_several_kinds_is_ambiguous
    assert_equal :ambiguous, @resolver.call("Dup")
  end

  def test_unknown_names_and_kinds_are_missing
    assert_equal :missing, @resolver.call("Nope")
    assert_equal :missing, @resolver.call("ApplicationComponent/Archsight:Web")
    assert_equal :missing, @resolver.call("NoSuchKind/Dup")
  end

  def test_the_path_is_escaped_but_keeps_colons
    assert_equal "/kinds/ApplicationService/instances/With%20Space%2Fx", @resolver.send(:path, "ApplicationService", "With Space/x")
    assert_includes @resolver.call("Archsight:Web"), "Archsight:Web"
  end
end
