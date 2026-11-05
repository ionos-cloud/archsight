# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class CapacityAnnotationsTest < Minitest::Test
  YAML_DOC = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyNode
    metadata:
      name: Node:Compute
      annotations:
        capacity/spareHosts: '2'
        link/source: https://example.org/capacity
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyEquipment
    metadata:
      name: Equipment:Block1
      annotations:
        equipment/type: cluster
        capacity/spareHosts: '1'
    spec: {}
  YAML

  def test_spare_hosts_is_a_count_on_nodes_and_equipment
    [Archsight::Resources::TechnologyNode, Archsight::Resources::TechnologyEquipment].each do |klass|
      annotation = klass.annotation_matching("capacity/spareHosts")

      refute_nil annotation, klass.name
      %w[0 1 12].each { |v| assert annotation.valid?(v), "#{klass} #{v}" }
      %w[-1 1.5 two].each { |v| refute annotation.valid?(v), "#{klass} #{v}" }
    end
  end

  def test_the_resources_load_and_lint_clean
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), YAML_DOC)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!

      assert_equal "2", db.instance_by_kind("TechnologyNode", "Node:Compute").annotations["capacity/spareHosts"]
      assert_empty Archsight::Linter.new(db).validate.grep(/spareHosts/)
    end
  end

  def test_a_device_has_no_spare_flag
    assert_nil Archsight::Resources::TechnologyDevice.annotation_matching("capacity/spareHosts")
  end
end
