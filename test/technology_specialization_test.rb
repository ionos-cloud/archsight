# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# specializes (node, system software, service) and composedOf (node, system software) between technology elements of
# one kind
class TechnologySpecializationTest < Minitest::Test
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyNode
    metadata:
      name: Node:Cluster
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyNode
    metadata:
      name: Node:ClusterX
    spec:
      specializes:
        technologyNodes:
          - Node:Cluster
      composedOf:
        technologyNodes:
          - Node:Host
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyNode
    metadata:
      name: Node:Host
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologySystemSoftware
    metadata:
      name: Soft:Platform
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologySystemSoftware
    metadata:
      name: Soft:PlatformX
    spec:
      specializes:
        technologySystemSoftware:
          - Soft:Platform
      composedOf:
        technologySystemSoftware:
          - Soft:Part
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologySystemSoftware
    metadata:
      name: Soft:Part
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: Service:Compute
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: Service:ComputeX
    spec:
      specializes:
        technologyServices:
          - Service:Compute
  YAML

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def lint(yaml)
    with_db(yaml) { |db| Archsight::Linter.new(db).validate }
  end

  # RESOURCES with `from` replaced; fails when it is not there, so a negative test cannot pass by testing nothing
  def changed(from, to)
    assert_includes RESOURCES, from
    RESOURCES.sub(from, to)
  end

  # `spec` of the empty resource `name` replaced by `spec`
  def with_spec(name, spec)
    changed("name: #{name}\nspec: {}", "name: #{name}\nspec:\n#{spec}")
  end

  def test_example_is_valid
    assert_empty lint(RESOURCES)
  end

  def test_node_specializes_node_and_the_general_node_lists_it
    with_db do |db|
      general = db.instance_by_kind("TechnologyNode", "Node:Cluster")
      specific = db.instance_by_kind("TechnologyNode", "Node:ClusterX")

      assert_equal [general], specific.relations(:specializes, :technologyNodes)
      assert_equal [specific], general.references_grouped.dig("TechnologyNode", :specializes)
    end
  end

  def test_node_is_composed_of_nodes_and_the_part_lists_the_whole
    with_db do |db|
      whole = db.instance_by_kind("TechnologyNode", "Node:ClusterX")
      part = db.instance_by_kind("TechnologyNode", "Node:Host")

      assert_equal [part], whole.relations(:composedOf, :technologyNodes)
      assert_equal [whole], part.references_grouped.dig("TechnologyNode", :composedOf)
    end
  end

  def test_system_software_specializes_and_is_composed_of_system_software
    with_db do |db|
      general = db.instance_by_kind("TechnologySystemSoftware", "Soft:Platform")
      specific = db.instance_by_kind("TechnologySystemSoftware", "Soft:PlatformX")
      part = db.instance_by_kind("TechnologySystemSoftware", "Soft:Part")

      assert_equal [general], specific.relations(:specializes, :technologySystemSoftware)
      assert_equal [part], specific.relations(:composedOf, :technologySystemSoftware)
      assert_equal [specific], general.references_grouped.dig("TechnologySystemSoftware", :specializes)
      assert_equal [specific], part.references_grouped.dig("TechnologySystemSoftware", :composedOf)
    end
  end

  def test_service_specializes_service_and_the_general_service_lists_it
    with_db do |db|
      general = db.instance_by_kind("TechnologyService", "Service:Compute")
      specific = db.instance_by_kind("TechnologyService", "Service:ComputeX")

      assert_equal [general], specific.relations(:specializes, :technologyServices)
      assert_equal [specific], general.references_grouped.dig("TechnologyService", :specializes)
    end
  end

  def test_specializes_target_must_be_the_same_kind
    {
      "technologyNodes:\n      - Node:Cluster" => "technologyNodes:\n      - Soft:Platform",
      "technologySystemSoftware:\n      - Soft:Platform" => "technologySystemSoftware:\n      - Node:Cluster",
      "technologyServices:\n      - Service:Compute" => "technologyServices:\n      - Node:Cluster"
    }.each do |from, to|
      assert_raises(Archsight::ResourceError, from) { with_db(changed(from, to)) { nil } }
    end
  end

  def test_composed_of_target_must_be_the_same_kind
    {
      "technologyNodes:\n      - Node:Host" => "technologyNodes:\n      - Soft:Part",
      "technologySystemSoftware:\n      - Soft:Part" => "technologySystemSoftware:\n      - Node:Host"
    }.each do |from, to|
      assert_raises(Archsight::ResourceError, from) { with_db(changed(from, to)) { nil } }
    end
  end

  def test_other_kinds_cannot_specialize_or_compose
    yaml = changed("kind: TechnologyNode\nmetadata:\n  name: Node:Host\nspec: {}",
                   "kind: TechnologyNode\nmetadata:\n  name: Node:Host\nspec:\n  specializes:\n    technologyArtifacts:\n      - Node:Cluster")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_service_cannot_be_composed_of_services
    yaml = changed("specializes:\n    technologyServices:\n      - Service:Compute",
                   "composedOf:\n    technologyServices:\n      - Service:Compute")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_specializes_cycle_is_reported
    errors = lint(with_spec("Node:Cluster", "  specializes:\n    technologyNodes:\n      - Node:ClusterX"))

    assert_equal 1, errors.length
    assert_match(/TechnologyNode 'Node:Cluster\w*' is part of a cycle of specializes relations \(Node:Cluster\w* -specializes-> Node:Cluster\w* -specializes-> Node:Cluster\w*\)/, errors.first)
  end

  def test_node_specializing_itself_is_reported
    errors = lint(with_spec("Node:Cluster", "  specializes:\n    technologyNodes:\n      - Node:Cluster"))

    assert_equal 1, errors.length
    assert_includes errors.first, "cycle of specializes relations (Node:Cluster -specializes-> Node:Cluster)"
  end

  def test_composed_of_cycle_is_reported
    errors = lint(with_spec("Node:Host", "  composedOf:\n    technologyNodes:\n      - Node:ClusterX"))

    assert_equal 1, errors.length
    assert_includes errors.first, "cycle of composedOf relations"
  end

  def test_system_software_cycle_is_reported
    errors = lint(with_spec("Soft:Platform", "  specializes:\n    technologySystemSoftware:\n      - Soft:PlatformX"))

    assert_equal 1, errors.length
    assert_includes errors.first, "cycle of specializes relations"
  end

  def test_different_verbs_between_two_elements_are_no_cycle
    # ClusterX specializes Cluster and composes Host; Host specializing Cluster closes no chain of one verb
    assert_empty lint(with_spec("Node:Host", "  specializes:\n    technologyNodes:\n      - Node:Cluster"))
  end

  def test_diamond_of_specializations_is_fine
    assert_empty lint(with_spec("Node:Host", "  specializes:\n    technologyNodes:\n      - Node:Cluster\n      - Node:ClusterX"))
  end

  def test_example_resources_list_implementations_on_the_concept
    db = Archsight::Database.new(File.expand_path("../examples/archsight", __dir__), verbose: false, compute_annotations: false)
    db.reload!
    concept = db.instance_by_kind("TechnologyNode", "Tech:RegionalCluster")
    implementation = db.instance_by_kind("TechnologyNode", "Tech:RegionalCluster:Hypervisor")

    assert_equal %w[Tech:RegionalCluster:BareMetal Tech:RegionalCluster:Hypervisor], concept.references_grouped.dig("TechnologyNode", :specializes).map(&:name).sort
    assert_equal [concept], implementation.relations_grouped.dig("specializes", "TechnologyNode")
  end
end
