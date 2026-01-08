# frozen_string_literal: true

require "test_helper"

class RendererTest < Minitest::Test
  include Archsight::GraphvisRenderer

  def setup
    @resources_dir = File.expand_path("../examples/archsight", __dir__)
    @db = Archsight::Database.new(@resources_dir, verbose: false)
    @db.reload!
  end

  def test_create_graph_all_returns_dot
    result = create_graph_all(@db, :draw_dot)

    assert_kind_of String, result
    assert_includes result, "digraph"
  end

  def test_create_graph_all_with_max_depth
    result = create_graph_all(@db, :draw_dot, max_depth: 1)

    assert_kind_of String, result
    assert_includes result, "digraph"
  end

  def test_create_graph_one_returns_dot
    klass = Archsight::Resources["TechnologyArtifact"]
    instances = @db.instances[klass]
    skip if instances.nil? || instances.empty?

    instance_name = instances.keys.first
    result = create_graph_one(@db, "TechnologyArtifact", instance_name, :draw_dot)

    assert_kind_of String, result
    assert_includes result, "digraph"
  end

  def test_create_graph_one_raises_for_unknown_kind
    assert_raises(RuntimeError) do
      create_graph_one(@db, "NonexistentKind", "test", :draw_dot)
    end
  end

  def test_create_graph_one_raises_for_unknown_instance
    assert_raises(RuntimeError) do
      create_graph_one(@db, "TechnologyArtifact", "NonexistentInstance", :draw_dot)
    end
  end

  def test_gname_returns_string
    instance = create_test_instance("TestName")
    result = gname(instance)

    assert_kind_of String, result
    assert_includes result, "TestName"
  end

  def test_css_class_includes_layer
    instance = create_test_instance("Test")
    result = css_class(instance)

    assert_match(/layer-/, result)
  end

  private

  def create_test_instance(name)
    klass = Archsight::Resources["TechnologyArtifact"]
    ref = Archsight::LineReference.new("test.yaml", 1)

    obj = {
      "apiVersion" => "architecture/v1alpha1",
      "kind" => "TechnologyArtifact",
      "metadata" => { "name" => name },
      "spec" => {}
    }

    klass.new(obj, ref)
  end
end
