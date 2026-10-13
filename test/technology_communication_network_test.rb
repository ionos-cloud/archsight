# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "rack/test"
require "archsight/web/application"
require "json"

# TechnologyCommunicationNetwork: logical networks with composedOf, specializes, servedBy, locatedAt and realizedBy
class TechnologyCommunicationNetworkTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Archsight::Web::Application
  end

  EXAMPLES = File.expand_path("../examples/archsight", __dir__)

  BASE = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: Location
    metadata:
      name: Location:Metro
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyFacility
    metadata:
      name: Facility:A
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyEquipment
    metadata:
      name: Equipment:Fabric
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologySystemSoftware
    metadata:
      name: Tech:Routing
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyNode
    metadata:
      name: Node:Router
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyCommunicationNetwork
    metadata:
      name: Net:Underlay
      annotations:
        network/type: underlay
    spec: {}
  YAML

  def network(name, relations = "{}", annotations: nil)
    meta = annotations ? "\n  annotations:\n#{annotations.lines.map { |l| "    #{l}" }.join}" : ""
    spec = relations == "{}" ? " {}" : "\n#{relations.lines.map { |line| "  #{line}" }.join.rstrip}"
    "---\napiVersion: architecture/v1alpha1\nkind: TechnologyCommunicationNetwork\nmetadata:\n  name: #{name}#{meta}\nspec:#{spec}\n"
  end

  def with_db(yaml = BASE)
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

  def load_error(yaml)
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }.to_s
  end

  def annotation(key)
    Archsight::Resources::TechnologyCommunicationNetwork.annotations.find { |a| a.key == key }
  end

  def test_the_kind_is_registered_in_the_technology_layer
    klass = Archsight::Resources["TechnologyCommunicationNetwork"]

    assert_equal "technology", klass.layer
    assert_equal "network", klass.icon
  end

  def test_type_and_topology_are_enums
    %w[underlay overlay management public vpn other].each { |v| assert annotation("network/type").valid?(v) }
    %w[mesh hub-and-spoke point-to-point ring other].each { |v| assert annotation("network/topology").valid?(v) }
    refute annotation("network/type").valid?("lan")
    refute annotation("network/topology").valid?("star")
  end

  def test_networks_nest_with_composed_of
    yaml = BASE + network("Net:Site") + network("Net:Metro", "composedOf:\n  technologyCommunicationNetworks:\n    - Net:Site")
    with_db(yaml) do |db|
      metro = db.instance_by_kind("TechnologyCommunicationNetwork", "Net:Metro")
      site = db.instance_by_kind("TechnologyCommunicationNetwork", "Net:Site")

      assert_equal [site], metro.relations(:composedOf, :technologyCommunicationNetworks)
      assert_equal [metro], site.references_grouped.dig("TechnologyCommunicationNetwork", :composedOf)
    end
  end

  def test_a_network_specializes_a_general_network
    yaml = BASE + network("Net:Impl", "specializes:\n  technologyCommunicationNetworks:\n    - Net:Underlay")
    with_db(yaml) do |db|
      general = db.instance_by_kind("TechnologyCommunicationNetwork", "Net:Underlay")

      assert_equal %w[Net:Impl], general.references_grouped.dig("TechnologyCommunicationNetwork", :specializes).map(&:name)
    end
  end

  def test_an_overlay_is_served_by_its_underlay
    yaml = BASE + network("Net:Overlay", "servedBy:\n  technologyCommunicationNetworks:\n    - Net:Underlay")
    with_db(yaml) do |db|
      underlay = db.instance_by_kind("TechnologyCommunicationNetwork", "Net:Underlay")

      assert_equal %w[Net:Overlay], underlay.references_grouped.dig("TechnologyCommunicationNetwork", :servedBy).map(&:name)
    end
  end

  def test_a_network_is_located_at_facilities_and_locations
    rel = "locatedAt:\n  technologyFacilities:\n    - Facility:A\n  locations:\n    - Location:Metro"
    with_db(BASE + network("Net:Metro", rel)) do |db|
      net = db.instance_by_kind("TechnologyCommunicationNetwork", "Net:Metro")

      assert_equal %w[Facility:A], net.relations(:locatedAt, :technologyFacilities).map(&:name)
      assert_equal %w[Location:Metro], net.relations(:locatedAt, :locations).map(&:name)
    end
  end

  def test_a_network_is_realized_by_equipment_and_system_software
    rel = "realizedBy:\n  technologyEquipment:\n    - Equipment:Fabric\n  technologySystemSoftware:\n    - Tech:Routing"
    with_db(BASE + network("Net:Overlay", rel)) do |db|
      net = db.instance_by_kind("TechnologyCommunicationNetwork", "Net:Overlay")

      assert_equal %w[Equipment:Fabric], net.relations(:realizedBy, :technologyEquipment).map(&:name)
      assert_equal %w[Tech:Routing], net.relations(:realizedBy, :technologySystemSoftware).map(&:name)
    end
  end

  def test_a_node_is_served_by_a_network_and_the_network_lists_it
    yaml = BASE.sub("name: Node:Router\nspec: {}", "name: Node:Router\nspec:\n  servedBy:\n    technologyCommunicationNetworks:\n      - Net:Underlay")
    with_db(yaml) do |db|
      net = db.instance_by_kind("TechnologyCommunicationNetwork", "Net:Underlay")

      assert_equal %w[Node:Router], net.references_grouped.dig("TechnologyNode", :servedBy).map(&:name)
    end
  end

  # --- wrong targets ---

  def test_composed_of_and_specializes_need_a_network
    %w[composedOf specializes servedBy].each do |verb|
      yaml = BASE + network("Net:Wrong", "#{verb}:\n  technologyCommunicationNetworks:\n    - Facility:A")

      assert_includes load_error(yaml), "Facility:A is not defined as kind", verb
    end
  end

  def test_located_at_and_realized_by_need_the_right_kinds
    assert_includes load_error(BASE + network("Net:Wrong", "locatedAt:\n  technologyFacilities:\n    - Node:Router")), "Node:Router is not defined as kind"
    assert_includes load_error(BASE + network("Net:Wrong", "realizedBy:\n  technologyEquipment:\n    - Node:Router")), "Node:Router is not defined as kind"
  end

  def test_a_node_cannot_be_served_by_a_non_network_through_the_network_key
    yaml = BASE.sub("name: Node:Router\nspec: {}", "name: Node:Router\nspec:\n  servedBy:\n    technologyCommunicationNetworks:\n      - Facility:A")

    assert_includes load_error(yaml), "Facility:A is not defined as kind"
  end

  # --- cycles ---

  def test_cycles_are_reported_for_each_hierarchy_verb
    { "composedOf" => /cycle of composedOf relations/, "specializes" => /cycle of specializes relations/,
      "servedBy" => /relation cycle/ }.each do |verb, pattern|
      yaml = BASE + network("Net:A", "#{verb}:\n  technologyCommunicationNetworks:\n    - Net:B") +
             network("Net:B", "#{verb}:\n  technologyCommunicationNetworks:\n    - Net:A")

      assert_predicate lint(yaml).grep(pattern), :any?, verb
    end
  end

  def test_a_chain_without_a_cycle_lints_clean
    yaml = BASE + network("Net:Overlay", "servedBy:\n  technologyCommunicationNetworks:\n    - Net:Underlay")

    assert_empty lint(yaml)
  end

  # --- realized by application software (issue #154) ---

  APPS = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: App:SDNAgent
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Service:TenantNetworking
    spec: {}
  YAML

  def test_an_overlay_is_realized_by_application_components_and_services
    rel = "realizedBy:\n  applicationComponents:\n    - App:SDNAgent\n  applicationServices:\n    - Service:TenantNetworking"
    with_db(BASE + APPS + network("Net:Tenant", rel)) do |db|
      net = db.instance_by_kind("TechnologyCommunicationNetwork", "Net:Tenant")
      agent = db.instance_by_kind("ApplicationComponent", "App:SDNAgent")

      assert_equal [agent], net.relations(:realizedBy, :applicationComponents)
      assert_equal %w[Service:TenantNetworking], net.relations(:realizedBy, :applicationServices).map(&:name)
      assert_equal [net], agent.references_grouped.dig("TechnologyCommunicationNetwork", :realizedBy)
    end
  end

  def test_realized_by_application_needs_the_right_kind
    yaml = BASE + APPS + network("Net:Wrong", "realizedBy:\n  applicationComponents:\n    - Service:TenantNetworking")

    assert_includes load_error(yaml), "Service:TenantNetworking is not defined as kind"
  end

  # The software runs on the nodes the network serves: realized by the component, the model has no cycle
  def test_software_on_the_served_nodes_realizes_the_network_without_a_cycle
    nodes = BASE.sub("name: Node:Router\nspec: {}", "name: Node:Router\nspec:\n  servedBy:\n    technologyCommunicationNetworks:\n      - Net:Tenant")
    yaml = nodes + APPS + network("Net:Tenant", "realizedBy:\n  applicationComponents:\n    - App:SDNAgent")

    assert_empty lint(yaml)
  end

  # Realized by the node's system software instead, the realization closes a cycle that lint reports
  def test_realized_by_the_served_nodes_system_software_is_a_cycle
    nodes = BASE.sub("name: Node:Router\nspec: {}", "name: Node:Router\nspec:\n  servedBy:\n    technologyCommunicationNetworks:\n      - Net:Tenant")
                .sub("name: Tech:Routing\nspec: {}", "name: Tech:Routing\nspec:\n  realizedBy:\n    technologyComponents:\n      - Node:Router")
    yaml = nodes + network("Net:Tenant", "realizedBy:\n  technologySystemSoftware:\n    - Tech:Routing")

    assert_predicate lint(yaml).grep(/relation cycle/), :any?
  end

  def test_the_example_tenant_overlay_is_realized_by_its_software
    db = Archsight::Database.new(EXAMPLES, verbose: false, compute_annotations: false)
    db.reload!
    tenant = db.instance_by_kind("TechnologyCommunicationNetwork", "Network:Overlay:Tenant")

    assert_equal %w[Network:Operator Network:SDNAgent], tenant.relations(:realizedBy, :applicationComponents).map(&:name)
  end

  # --- the example ---

  def use_examples
    Archsight.resources_dir = EXAMPLES
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
  end

  def test_the_instance_api_lists_the_nodes_on_a_network
    use_examples
    get "/api/v1/kinds/TechnologyCommunicationNetwork/instances/Network:Management:Frankfurt"

    assert_predicate last_response, :ok?
    references = JSON.parse(last_response.body)["references"]

    assert_includes references.dig("TechnologyNode", "servedBy"), "Node:Frankfurt:Web01"
  end

  def test_the_examples_model_overlay_vpn_mesh_and_metro_networks
    db = Archsight::Database.new(EXAMPLES, verbose: false, compute_annotations: false)
    db.reload!

    assert_empty Archsight::Linter.new(db).validate
    overlay = db.instance_by_kind("TechnologyCommunicationNetwork", "Network:Overlay:EVPN")

    assert_equal %w[Network:Underlay:Frankfurt-Madrid], overlay.relations(:servedBy, :technologyCommunicationNetworks).map(&:name)
    metro = db.instance_by_kind("TechnologyCommunicationNetwork", "Network:Metro:Frankfurt")

    assert_equal %w[Location:Germany:Frankfurt], metro.relations(:locatedAt, :locations).map(&:name)
    assert_equal %w[Network:Overlay:EVPN Network:Overlay:Tenant], db.query('TechnologyCommunicationNetwork: network/type == "overlay"').map(&:name).sort
    assert_equal %w[Network:Overlay:EVPN], db.query('TechnologyCommunicationNetwork: network/topology == "mesh"').map(&:name)
  end
end
