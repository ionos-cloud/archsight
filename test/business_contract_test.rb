# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class BusinessContractTest < Minitest::Test
  # The example of the issue, with the resources it points to
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: ComputeService
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: ObjectStorage
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: CustomerOrg
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: ProviderOrg
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyEquipment
    metadata:
      name: Block2
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationDeliverable
    metadata:
      name: Block2Delivered
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessProduct
    metadata:
      name: PrivateCloudOffering
    spec:
      servedBy:
        applicationServices: [ComputeService, ObjectStorage]
      aggregates:
        businessContracts: [Contract:Customer]
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessContract
    metadata:
      name: Contract:Customer
      annotations:
        contract/type: framework
        contract/from: '2024-01-01'
    spec:
      agreedBy:
        businessActors: [CustomerOrg, ProviderOrg]
      composedOf:
        businessContracts: [Contract:Customer:Block1, Contract:Customer:Block2]
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessContract
    metadata:
      name: Contract:Customer:Block1
      annotations:
        contract/type: call-off
    spec:
      covers:
        applicationServices: [ComputeService]
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessContract
    metadata:
      name: Contract:Customer:Block2
      annotations:
        contract/type: call-off
    spec:
      covers:
        technologyEquipment: [Block2]
      realizedThrough:
        implementationDeliverables: [Block2Delivered]
    ---
    apiVersion: architecture/v1alpha1
    kind: ImplementationWorkPackage
    metadata:
      name: BuildBlock2
    spec:
      realizes:
        implementationDeliverables: [Block2Delivered]
      affects:
        technologyEquipment: [Block2]
  YAML

  def with_db(yaml = RESOURCES, compute: false)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: compute)
      db.reload!
      yield db
    end
  end

  def instance(db, kind, name) = db.instance_by_kind(kind, name)

  def incoming(inst, kind, verb) = (inst.references_grouped.dig(kind, verb) || []).map(&:name).sort

  def annotation(key) = Archsight::Resources::BusinessContract.annotation_matching(key)

  def test_the_kind_is_a_business_contract_with_its_own_icon
    klass = Archsight::Resources::BusinessContract

    assert_equal "business", klass.layer
    assert_equal "journal-page", klass.icon
    assert_includes klass.description, "agreedBy"
  end

  def test_the_example_loads_and_links_both_ways
    with_db do |db|
      product = instance(db, "BusinessProduct", "PrivateCloudOffering")
      framework = instance(db, "BusinessContract", "Contract:Customer")
      block2 = instance(db, "BusinessContract", "Contract:Customer:Block2")
      equipment = instance(db, "TechnologyEquipment", "Block2")

      assert_equal ["Contract:Customer"], product.relations(:aggregates, :businessContracts).map(&:name)
      assert_equal %w[CustomerOrg ProviderOrg], framework.relations(:agreedBy, :businessActors).map(&:name)
      assert_equal %w[Contract:Customer:Block1 Contract:Customer:Block2], framework.relations(:composedOf, :businessContracts).map(&:name)
      assert_equal ["Block2Delivered"], block2.relations(:realizedThrough, :implementationDeliverables).map(&:name)

      assert_equal ["Contract:Customer"], incoming(instance(db, "BusinessActor", "CustomerOrg"), "BusinessContract", :agreedBy)
      assert_equal ["Contract:Customer:Block2"], incoming(equipment, "BusinessContract", :covers)
      assert_equal ["BuildBlock2"], incoming(equipment, "ImplementationWorkPackage", :affects)
      assert_equal ["Contract:Customer:Block2"], incoming(instance(db, "ImplementationDeliverable", "Block2Delivered"), "BusinessContract", :realizedThrough)
      assert_equal ["PrivateCloudOffering"], incoming(framework, "BusinessProduct", :aggregates)
    end
  end

  def test_the_example_lints_clean
    with_db { |db| assert_empty Archsight::Linter.new(db).validate }
  end

  def test_type_and_dates_are_checked
    assert annotation("contract/type").valid?("call-off")
    refute annotation("contract/type").valid?("handshake")
    assert annotation("contract/from").valid?("2024-01-01")
    refute annotation("contract/until").valid?("soon")
  end

  def test_a_contract_cannot_cover_a_product
    yaml = RESOURCES.sub("    technologyEquipment: [Block2]\n  realizedThrough:",
                         "    businessProducts: [PrivateCloudOffering]\n  realizedThrough:")

    refute_equal RESOURCES, yaml
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_lint_reports_a_cycle_of_contract_parts
    yaml = RESOURCES.sub("  realizedThrough:\n    implementationDeliverables: [Block2Delivered]",
                         "  realizedThrough:\n    implementationDeliverables: [Block2Delivered]\n  composedOf:\n    businessContracts: [Contract:Customer]")

    refute_equal RESOURCES, yaml
    with_db(yaml) do |db|
      errors = Archsight::Linter.new(db).validate

      cycle = errors.grep(/cycle of composedOf/)

      assert(cycle.any? { |e| e.include?("Contract:Customer") }, "no composedOf cycle reported")
    end
  end
end
