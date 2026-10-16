# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class TechnologyDeviceTest < Minitest::Test
  # Two rooms, a server per room cabled to the switch member of its room, a virtual chassis of both members, a
  # router, a rack, a logical node and a network
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyFacility
    metadata:
      name: DC
      annotations:
        facility/type: data-center
    spec:
      composedOf:
        technologyFacilities: [Room1, Room2]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyFacility
    metadata:
      name: Room1
      annotations:
        facility/type: room
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyFacility
    metadata:
      name: Room2
      annotations:
        facility/type: room
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyDevice
    metadata:
      name: Server1
      annotations:
        device/type: server
        device/role: hypervisor
    spec:
      locatedAt:
        technologyFacilities: [Room1]
      connectedTo:
        technologyDevices: [SwitchN0]
      ownedBy:
        businessActors: [Team:Ops]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyDevice
    metadata:
      name: Server2
      annotations:
        device/type: server
        device/purpose: kernel regression tests
    spec:
      locatedAt:
        technologyFacilities: [Room2]
      connectedTo:
        technologyDevices: [SwitchN1]
      servedBy:
        businessActors: [Team:QA]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyDevice
    metadata:
      name: SwitchN0
      annotations:
        device/type: switch
    spec:
      locatedAt:
        technologyFacilities: [Room1]
      connectedTo:
        technologyDevices: [SwitchN1]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyDevice
    metadata:
      name: SwitchN1
      annotations:
        device/type: switch
    spec:
      locatedAt:
        technologyFacilities: [Room2]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyDevice
    metadata:
      name: CoreSwitch
      annotations:
        device/type: switch
    spec:
      composedOf:
        technologyDevices: [SwitchN0, SwitchN1]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyDevice
    metadata:
      name: Router1
      annotations:
        device/type: router
    spec:
      locatedAt:
        technologyFacilities: [Room1]
      connectedTo:
        technologyDevices: [SwitchN0, SwitchN1]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyEquipment
    metadata:
      name: Rack1
      annotations:
        equipment/type: rack
        equipment/purpose: hypervisor regression tests
    spec:
      locatedAt:
        technologyFacilities: [Room1]
      composedOf:
        technologyDevices: [Server1]
      ownedBy:
        businessRoles: [Role:DeviceOwner]
      servedBy:
        businessActors: [Team:QA]
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Ops
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:QA
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessRole
    metadata:
      name: Role:DeviceOwner
    spec:
      performedBy:
        businessActors: [Team:Ops]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyNode
    metadata:
      name: Hypervisors
    spec:
      realizedBy:
        technologyDevices: [Server1, Server2]
      ownedBy:
        businessActors: [Team:Ops]
      servedBy:
        businessActors: [Team:QA]
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyCommunicationNetwork
    metadata:
      name: Management
      annotations:
        network/type: management
    spec:
      realizedBy:
        technologyDevices: [CoreSwitch, Router1]
      connects:
        technologyDevices: [Server1, Server2]
      ownedBy:
        businessRoles: [Role:DeviceOwner]
  YAML

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def instance(db, kind, name) = db.instance_by_kind(kind, name)

  def incoming(inst, kind, verb) = (inst.references_grouped.dig(kind, verb) || []).map(&:name).sort

  def device_warnings(db) = Archsight::Linter.new(db).structural_warnings.grep(/TechnologyDevice/)

  def test_the_kind_is_a_technology_device_with_its_own_icon
    klass = Archsight::Resources::TechnologyDevice

    assert_equal "technology", klass.layer
    assert_equal "server", klass.icon
    assert_includes klass.description, "connectedTo"
  end

  def test_the_example_loads_and_links_both_ways
    with_db do |db|
      server = instance(db, "TechnologyDevice", "Server1")
      member = instance(db, "TechnologyDevice", "SwitchN0")

      assert_equal ["Room1"], server.relations(:locatedAt, :technologyFacilities).map(&:name)
      assert_equal ["SwitchN0"], server.relations(:connectedTo, :technologyDevices).map(&:name)
      assert_equal %w[Router1 Server1], incoming(member, "TechnologyDevice", :connectedTo)
      assert_equal ["CoreSwitch"], incoming(member, "TechnologyDevice", :composedOf)
      assert_equal ["Hypervisors"], incoming(server, "TechnologyNode", :realizedBy)
      assert_equal ["Management"], incoming(server, "TechnologyCommunicationNetwork", :connects)
      assert_equal ["Management"], incoming(instance(db, "TechnologyDevice", "CoreSwitch"), "TechnologyCommunicationNetwork", :realizedBy)
      assert_equal ["Rack1"], incoming(server, "TechnologyEquipment", :composedOf)
      assert_equal %w[Router1 Server1 SwitchN0], incoming(instance(db, "TechnologyFacility", "Room1"), "TechnologyDevice", :locatedAt)
    end
  end

  def test_teams_own_and_are_served_by_devices_equipment_nodes_and_networks
    with_db do |db|
      ops = instance(db, "BusinessActor", "Team:Ops")
      qa = instance(db, "BusinessActor", "Team:QA")
      owner = instance(db, "BusinessRole", "Role:DeviceOwner")

      assert_equal ["Server1"], incoming(ops, "TechnologyDevice", :ownedBy)
      assert_equal ["Hypervisors"], incoming(ops, "TechnologyNode", :ownedBy)
      assert_equal ["Server2"], incoming(qa, "TechnologyDevice", :servedBy)
      assert_equal ["Rack1"], incoming(qa, "TechnologyEquipment", :servedBy)
      assert_equal ["Hypervisors"], incoming(qa, "TechnologyNode", :servedBy)
      assert_equal ["Rack1"], incoming(owner, "TechnologyEquipment", :ownedBy)
      assert_equal ["Management"], incoming(owner, "TechnologyCommunicationNetwork", :ownedBy)
    end
  end

  def test_purpose_is_free_text_on_devices_and_equipment
    with_db do |db|
      assert_equal "kernel regression tests", instance(db, "TechnologyDevice", "Server2").annotations["device/purpose"]
      assert_equal "hypervisor regression tests", instance(db, "TechnologyEquipment", "Rack1").annotations["equipment/purpose"]
    end
  end

  def test_warns_about_a_device_served_apart_from_its_partition
    yaml = RESOURCES.sub("  ownedBy:\n    businessActors: [Team:Ops]\n---\n",
                         "  ownedBy:\n    businessActors: [Team:Ops]\n  servedBy:\n    businessActors: [Team:Ops]\n---\n")

    refute_equal RESOURCES, yaml
    with_db(yaml) do |db|
      messages = device_warnings(db).map { |w| w.sub(/\A.*?: /, "") }

      assert_equal ["TechnologyDevice 'Server1' is servedBy 'Team:Ops', not by the team of its equipment ('Team:QA')"], messages
    end
  end

  def test_a_device_served_like_its_partition_or_not_at_all_is_fine
    yaml = RESOURCES.sub("  ownedBy:\n    businessActors: [Team:Ops]\n---\n",
                         "  ownedBy:\n    businessActors: [Team:Ops]\n  servedBy:\n    businessActors: [Team:QA]\n---\n")

    refute_equal RESOURCES, yaml
    with_db(yaml) { |db| assert_empty device_warnings(db) }
    with_db { |db| assert_empty device_warnings(db) } # Server1 names no team: served through Rack1
  end

  def test_the_example_lints_clean_and_without_device_warnings
    with_db do |db|
      assert_empty Archsight::Linter.new(db).validate
      assert_empty device_warnings(db)
    end
  end

  def test_type_and_room_are_checked
    device_type = Archsight::Resources::TechnologyDevice.annotation_matching("device/type")
    facility_type = Archsight::Resources::TechnologyFacility.annotation_matching("facility/type")

    assert device_type.valid?("terminal-server")
    refute device_type.valid?("toaster")
    assert facility_type.valid?("room")
  end

  def test_a_device_cannot_be_located_at_a_node
    yaml = RESOURCES.sub("  locatedAt:\n    technologyFacilities: [Room2]\n  connectedTo:",
                         "  locatedAt:\n    technologyNodes: [Hypervisors]\n  connectedTo:")

    refute_equal RESOURCES, yaml
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }
  end

  def test_cabling_both_ways_is_no_cycle
    yaml = RESOURCES.sub("    technologyFacilities: [Room2]\n---",
                         "    technologyFacilities: [Room2]\n  connectedTo:\n    technologyDevices: [SwitchN0]\n---")

    refute_equal RESOURCES, yaml
    with_db(yaml) { |db| assert_empty Archsight::Linter.new(db).validate }
  end

  def test_warns_about_an_unplaced_device
    yaml = RESOURCES.sub("  locatedAt:\n    technologyFacilities: [Room2]\n  connectedTo:", "  connectedTo:")

    with_db(yaml) do |db|
      messages = device_warnings(db).map { |w| w.sub(/\A.*?: /, "") }

      assert_equal ["TechnologyDevice 'Server2' is located at no TechnologyFacility"], messages
    end
  end

  def test_a_racked_device_and_a_chassis_need_no_room_of_their_own
    yaml = RESOURCES.sub("    device/role: hypervisor\nspec:\n  locatedAt:\n    technologyFacilities: [Room1]\n",
                         "    device/role: hypervisor\nspec:\n")

    refute_equal RESOURCES, yaml
    with_db(yaml) { |db| assert_empty device_warnings(db) } # Server1 is in Rack1, CoreSwitch has placed members
  end

  def test_warns_about_a_device_cabled_to_itself
    yaml = RESOURCES.sub("    technologyDevices: [SwitchN0, SwitchN1]\n---\napiVersion: architecture/v1alpha1\nkind: TechnologyEquipment",
                         "    technologyDevices: [SwitchN0, SwitchN1, Router1]\n---\napiVersion: architecture/v1alpha1\nkind: TechnologyEquipment")

    refute_equal RESOURCES, yaml
    with_db(yaml) { |db| assert(device_warnings(db).any? { |w| w.include?("'Router1' is connectedTo itself") }) }
  end

  def test_warns_about_a_router_that_realizes_no_network_but_not_about_chassis_members
    yaml = RESOURCES.sub("technologyDevices: [CoreSwitch, Router1]", "technologyDevices: [CoreSwitch]")

    refute_equal RESOURCES, yaml
    with_db(yaml) do |db|
      warnings = device_warnings(db)

      assert(warnings.any? { |w| w.include?("'Router1' is a router that realizes no TechnologyCommunicationNetwork") })
      refute(warnings.any? { |w| w.include?("SwitchN0") }, "a chassis member realizes the network through its chassis")
    end
  end

  def test_devices_are_reached_top_down_and_lead_back_to_nothing_above_them
    edges = Archsight::Resources.resource_classes.to_h do |kind, klass|
      [kind, klass.declared_relations.map { |_verb, _key, target| target.to_s }.uniq]
    end
    reachable = lambda do |start|
      seen = Set.new
      queue = [start]
      while (kind = queue.shift)
        (edges[kind] || []).each do |target|
          next if seen.include?(target)

          seen << target
          queue << target
        end
      end
      seen
    end

    %w[TechnologyNode TechnologyCommunicationNetwork TechnologyEquipment].each do |kind|
      assert_includes reachable.call(kind), "TechnologyDevice"
      refute_includes reachable.call("TechnologyDevice"), kind, "a device must not lead back to #{kind}"
    end
    %w[BusinessActor BusinessRole].each do |kind|
      assert_includes reachable.call("TechnologyDevice"), kind
      %w[TechnologyDevice TechnologyEquipment TechnologyNode TechnologyCommunicationNetwork].each do |technology|
        refute_includes reachable.call(kind), technology, "#{kind} must not lead back to #{technology}"
      end
    end
  end
end
