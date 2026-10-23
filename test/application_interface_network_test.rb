# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "archsight/analysis"

# An ApplicationInterface is servedBy the networks on which it can be reached (issue #200)
class ApplicationInterfaceNetworkTest < Minitest::Test
  YAML_DOCS = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyCommunicationNetwork
    metadata:
      name: Net:Office
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyCommunicationNetwork
    metadata:
      name: Net:Partner
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationInterface
    metadata:
      name: Vault:Lookup
      annotations:
        api/authenticationMethod: none
    spec:
      servedBy:
        technologyCommunicationNetworks:
          - Net:Office
          - Net:Partner
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationInterface
    metadata:
      name: Vault:Unplaced
      annotations:
        api/authenticationMethod: none
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Gateway
    spec:
      dependsOn:
        applicationInterfaces:
          - Vault:Lookup
          - Vault:Unplaced
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Vault
    spec:
      exposes:
        applicationInterfaces:
          - Vault:Lookup
  YAML

  def with_db(yaml = YAML_DOCS)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def test_the_relation_is_declared_next_to_the_technology_interface
    relations = Archsight::Resources["ApplicationInterface"].declared_relations

    assert_includes relations, %i[servedBy technologyCommunicationNetworks TechnologyCommunicationNetwork]
    assert_includes relations, %i[servedBy technologyComponents TechnologyInterface]
  end

  def test_an_interface_is_served_by_its_networks
    with_db do |db|
      interface = db.instance_by_kind("ApplicationInterface", "Vault:Lookup")

      assert_equal %w[Net:Office Net:Partner], interface.relations(:servedBy, :technologyCommunicationNetworks).map(&:name).sort
    end
  end

  def test_the_network_lists_the_interfaces_it_carries
    with_db do |db|
      network = db.instance_by_kind("TechnologyCommunicationNetwork", "Net:Office")

      assert_equal %w[Vault:Lookup], network.references_grouped.dig("ApplicationInterface", :servedBy).map(&:name)
    end
  end

  def test_an_interface_without_networks_is_valid_and_makes_no_claim
    with_db do |db|
      assert_empty(Archsight::Linter.new(db).validate.to_a.select { |problem| problem.to_s.include?("Vault:Unplaced") })
      assert_empty db.instance_by_kind("ApplicationInterface", "Vault:Unplaced").relations(:servedBy, :technologyCommunicationNetworks)
    end
  end

  def test_a_network_must_be_a_network
    yaml = YAML_DOCS.sub("- Net:Partner", "- Gateway")

    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_the_example_analysis_lists_unauthenticated_interfaces_with_networks_and_callers
    db = Archsight::Database.new(File.expand_path("../examples/archsight", __dir__), verbose: false, compute_annotations: false)
    db.reload!
    analysis = db.instance_by_kind("Analysis", "Analysis:Interface:ExposedWithoutAuthentication")
    result = Archsight::Analysis::Executor.new(db).execute(analysis)
    table = result.sections.find { |section| section[:type] == :table }

    assert_predicate result, :success?
    assert_equal [["CardVault:Lookup", "Network:Management:Frankfurt, Network:Overlay:Tenant", "Payments:API"]], table[:rows]
  end
end
