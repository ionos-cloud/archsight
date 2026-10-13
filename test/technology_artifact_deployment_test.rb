# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# artifact/type image, TechnologyArtifact aggregates artifacts, TechnologyNode / TechnologySystemSoftware assignedTo
# artifacts
class TechnologyArtifactDeploymentTest < Minitest::Test
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyNode
    metadata:
      name: Node:Hypervisor
    spec:
      assignedTo:
        technologyArtifacts:
          - Art:Image
          - Art:Metrics
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologySystemSoftware
    metadata:
      name: Soft:ConfigManagement
    spec:
      assignedTo:
        technologyArtifacts:
          - Art:Metrics
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyArtifact
    metadata:
      name: Art:Image
      annotations:
        artifact/type: image
    spec:
      aggregates:
        technologyArtifacts:
          - Art:VirtAgent
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyArtifact
    metadata:
      name: Art:VirtAgent
      annotations:
        artifact/type: deb
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyArtifact
    metadata:
      name: Art:Metrics
      annotations:
        artifact/type: rpm
    spec: {}
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

  def test_example_is_valid
    assert_empty lint(RESOURCES)
  end

  def test_image_binary_and_archive_are_artifact_types
    annotation = Archsight::Resources::TechnologyArtifact.annotations.find { |a| a.key == "artifact/type" }

    assert_empty annotation.validate("image")
    assert_empty annotation.validate("binary")
    assert_empty annotation.validate("archive")
    refute_empty annotation.validate("floppy")
  end

  def test_artifact_aggregates_artifacts_and_the_content_lists_where_it_is_contained
    with_db do |db|
      image = db.instance_by_kind("TechnologyArtifact", "Art:Image")
      package = db.instance_by_kind("TechnologyArtifact", "Art:VirtAgent")

      assert_equal [package], image.relations(:aggregates, :technologyArtifacts)
      assert_equal [image], package.references_grouped.dig("TechnologyArtifact", :aggregates)
    end
  end

  def test_node_is_assigned_to_artifacts_and_the_artifact_lists_the_node
    with_db do |db|
      node = db.instance_by_kind("TechnologyNode", "Node:Hypervisor")
      image = db.instance_by_kind("TechnologyArtifact", "Art:Image")

      assert_equal %w[Art:Image Art:Metrics], node.relations(:assignedTo, :technologyArtifacts).map(&:name)
      assert_equal [node], image.references_grouped.dig("TechnologyNode", :assignedTo)
    end
  end

  def test_system_software_is_assigned_to_artifacts_and_the_artifact_lists_it
    with_db do |db|
      software = db.instance_by_kind("TechnologySystemSoftware", "Soft:ConfigManagement")
      metrics = db.instance_by_kind("TechnologyArtifact", "Art:Metrics")

      assert_equal [metrics], software.relations(:assignedTo, :technologyArtifacts)
      assert_equal [software], metrics.references_grouped.dig("TechnologySystemSoftware", :assignedTo)
      assert_equal %w[Node:Hypervisor], metrics.references_grouped.dig("TechnologyNode", :assignedTo).map(&:name)
    end
  end

  def test_assigned_to_and_aggregates_targets_must_be_artifacts
    {
      "technologyArtifacts:\n      - Art:Image\n      - Art:Metrics" => "technologyArtifacts:\n      - Soft:ConfigManagement",
      "technologyArtifacts:\n      - Art:VirtAgent" => "technologyArtifacts:\n      - Node:Hypervisor"
    }.each do |from, to|
      assert_raises(Archsight::ResourceError, from) { with_db(changed(from, to)) { nil } }
    end
  end

  def test_other_kinds_cannot_use_assigned_to_or_aggregates
    yaml = changed("name: Art:Metrics\n  annotations:\n    artifact/type: rpm\nspec: {}",
                   "name: Art:Metrics\n  annotations:\n    artifact/type: rpm\nspec:\n  assignedTo:\n    technologyArtifacts:\n      - Art:Image")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_aggregates_cycle_is_reported
    errors = lint(changed("name: Art:VirtAgent\n  annotations:\n    artifact/type: deb\nspec: {}",
                          "name: Art:VirtAgent\n  annotations:\n    artifact/type: deb\nspec:\n  aggregates:\n    technologyArtifacts:\n      - Art:Image"))

    assert_equal 1, errors.length
    assert_match(/TechnologyArtifact 'Art:\w+' is part of a cycle of aggregates relations \(Art:\w+ -aggregates-> Art:\w+ -aggregates-> Art:\w+\)/, errors.first)
  end

  def test_artifact_aggregating_itself_is_reported
    errors = lint(changed("name: Art:Metrics\n  annotations:\n    artifact/type: rpm\nspec: {}",
                          "name: Art:Metrics\n  annotations:\n    artifact/type: rpm\nspec:\n  aggregates:\n    technologyArtifacts:\n      - Art:Metrics"))

    assert_equal 1, errors.length
    assert_includes errors.first, "cycle of aggregates relations (Art:Metrics -aggregates-> Art:Metrics)"
  end

  def test_shared_content_is_not_a_cycle
    # image and a second image both contain the same package
    yaml = changed("name: Art:Metrics\n  annotations:\n    artifact/type: rpm\nspec: {}",
                   "name: Art:Metrics\n  annotations:\n    artifact/type: rpm\nspec:\n  aggregates:\n    technologyArtifacts:\n      - Art:VirtAgent")

    assert_empty lint(yaml)
  end

  def test_example_resources_describe_the_deployment_of_an_image
    db = Archsight::Database.new(File.expand_path("../examples/archsight", __dir__), verbose: false, compute_annotations: false)
    db.reload!
    image = db.instance_by_kind("TechnologyArtifact", "Tech:Image:Hypervisor")

    assert_equal "image", image.annotations["artifact/type"]
    assert_equal %w[Tech:Package:NetAgent Tech:Package:VirtAgent], image.relations(:aggregates, :technologyArtifacts).map(&:name).sort
    assert_equal ["Tech:Host:Hypervisor"], image.references_grouped.dig("TechnologyNode", :assignedTo).map(&:name)
  end
end
