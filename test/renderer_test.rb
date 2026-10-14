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
    result = create_graph_all(@db)

    assert_kind_of String, result
    assert_includes result, "digraph"
  end

  def test_create_graph_all_with_max_depth
    result = create_graph_all(@db, max_depth: 1)

    assert_kind_of String, result
    assert_includes result, "digraph"
  end

  def test_create_graph_one_returns_dot
    klass = Archsight::Resources["TechnologyArtifact"]
    instances = @db.instances[klass]
    skip if instances.nil? || instances.empty?

    instance_name = instances.keys.first
    result = create_graph_one(@db, "TechnologyArtifact", instance_name)

    assert_kind_of String, result
    assert_includes result, "digraph"
  end

  def test_create_graph_one_raises_for_unknown_kind
    assert_raises(RuntimeError) do
      create_graph_one(@db, "NonexistentKind", "test")
    end
  end

  def test_create_graph_one_raises_for_unknown_instance
    assert_raises(RuntimeError) do
      create_graph_one(@db, "TechnologyArtifact", "NonexistentInstance")
    end
  end

  def test_create_graph_one_with_a_depth_stops_and_marks_the_cut
    root, direct = deep_instance
    one = create_graph_one(@db, root.klass, root.name, max_depth: 1)
    nodes = graph_nodes(one)

    assert_equal ([gname(root)] + direct.map { |inst| gname(inst) }).uniq.sort, nodes.sort
    assert_includes one, "dashed", "a direct target with relations of its own is drawn dashed"
    assert_operator graph_nodes(create_graph_one(@db, root.klass, root.name)).size, :>, nodes.size
  end

  def test_create_graph_one_without_a_depth_is_unchanged
    root, = deep_instance
    full = create_graph_one(@db, root.klass, root.name)

    refute_includes full, "dashed"
  end

  def test_create_graph_one_follows_only_the_selected_layers
    # e.g. a repository: technology relations and the team that maintains it
    stack = %w[application technology]
    root = @db.instances.values.flat_map(&:values).find do |inst|
      layers = graph_targets(inst, nil).map { |_, rel| rel.class.layer }
      layers.include?("technology") && layers.any? { |layer| !stack.include?(layer) }
    end
    skip("no resource with technology and other relations") unless root

    all = graph_nodes(create_graph_one(@db, root.klass, root.name, max_depth: 1))
    selected = graph_nodes(create_graph_one(@db, root.klass, root.name, max_depth: 1, layers: stack))
    layers = selected.map { |node| Archsight::Resources[node.split("/", 2).first.split("::").last].layer }

    assert_operator all.size, :>, selected.size
    assert_includes layers, "technology"
    assert(layers.drop(1).all? { |layer| stack.include?(layer) })
  end

  def test_the_default_layers_are_the_own_and_the_next_below
    renderer = Archsight::GraphvisRenderer

    assert_equal %w[application technology], renderer.default_graph_layers("application")
    assert_equal %w[motivation strategy], renderer.default_graph_layers("motivation")
    assert_equal %w[technology], renderer.default_graph_layers("technology")
    assert_equal Archsight::Resources::LAYERS, renderer.default_graph_layers("other")
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

  # An instance whose direct targets have relations of their own, and those targets
  def deep_instance
    @db.instances.each_value do |instances|
      instances.each_value do |inst|
        direct = graph_targets(inst, nil).map(&:last)
        return [inst, direct] if direct.any? { |rel| graph_targets(rel, nil).any? { |_, deeper| deeper != inst && !direct.include?(deeper) } }
      end
    end
    skip("no instance with a graph deeper than one step")
  end

  def graph_nodes(dot)
    dot.scan(/^\s*"([^"]+)" \[/).flatten.uniq
  end

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
