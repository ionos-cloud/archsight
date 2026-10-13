# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "rack/test"
require "archsight/web/application"
require "archsight/cli"
require "json"

# Location, Facility and Equipment (physical layer) and the locatedAt / composedOf relations (issue #135)
class PhysicalLayerTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Archsight::Web::Application
  end

  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessActor
    metadata:
      name: Team:Ops
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: Location
    metadata:
      name: Location:Germany
      annotations:
        location/country: Germany
        location/city: Frankfurt
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: Facility
    metadata:
      name: Facility:Campus
      annotations:
        facility/type: data-center
        facility/stage: productive
    spec:
      locatedAt:
        locations:
          - Location:Germany
      composedOf:
        facilities:
          - Facility:HallA
          - Facility:HallB
      servedBy:
        businessActors:
          - Team:Ops
    ---
    apiVersion: architecture/v1alpha1
    kind: Facility
    metadata:
      name: Facility:HallA
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: Facility
    metadata:
      name: Facility:HallB
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: Equipment
    metadata:
      name: Equipment:Rack01
      annotations:
        equipment/type: rack
    spec:
      locatedAt:
        facilities:
          - Facility:HallA
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyNode
    metadata:
      name: Node:Web01
    spec:
      locatedAt:
        facilities:
          - Facility:HallA
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologySystemSoftware
    metadata:
      name: Software:Cluster
    spec:
      locatedAt:
        facilities:
          - Facility:HallA
          - Facility:HallB
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: Service:Orders
    spec:
      locatedAt:
        facilities:
          - Facility:HallA
          - Facility:HallB
  YAML

  EXAMPLES = File.expand_path("../examples/archsight", __dir__)

  # A further document appended to the model above
  def extra(kind, name, relations)
    <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: #{kind}
      metadata:
        name: #{name}
      spec:
      #{relations.lines.map { |line| "  #{line}" }.join.rstrip}
    YAML
  end

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

  def load_error(yaml)
    assert_raises(Archsight::ResourceError) { with_db(yaml) { nil } }.to_s
  end

  def use_examples
    Archsight.resources_dir = EXAMPLES
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
  end

  # --- the kinds load, lint and render with icons ---

  def test_the_three_kinds_are_registered_with_icon_and_layer
    { "Location" => "map-pin", "Facility" => "building", "Equipment" => "cpu" }.each do |kind, icon|
      klass = Archsight::Resources[kind]

      assert_equal icon, klass.icon, kind
      assert_equal "physical", klass.layer, kind
      refute_empty klass.description.to_s, kind
    end
  end

  def test_kinds_api_lists_them_with_icon_and_layer
    use_examples
    get "/api/v1/kinds"
    kinds = JSON.parse(last_response.body)["kinds"].to_h { |k| [k["kind"], k] }

    %w[Location Facility Equipment].each do |kind|
      assert_equal "physical", kinds.fetch(kind)["layer"]
      assert kinds.fetch(kind)["icon"]
      assert_predicate kinds.fetch(kind)["instance_count"], :positive?, "#{kind} has an example"
    end
  end

  def test_physical_layer_is_known_to_the_frontend_and_the_documentation
    root = File.expand_path("..", __dir__)

    assert_includes File.read(File.join(root, "frontend/src/composables/useLayers.js")), "id: 'physical'"
    assert_includes File.read(File.join(root, "frontend/src/css/base.css")), ".icon-physical"
    assert_includes File.read(File.join(root, "frontend/src/css/graph.css")), ".layer-physical"
    assert_includes Archsight::Documentation::LAYER_ORDER, "physical"
  end

  def test_the_model_loads_and_lints_clean
    with_db do |db|
      assert_empty Archsight::Linter.new(db).validate
      assert_equal 3, db.instances_by_kind("Facility").length
    end
  end

  def test_annotations
    facility_type = Archsight::Resources::Facility.annotations.find { |a| a.key == "facility/type" }

    assert facility_type.valid?("colocation")
    refute facility_type.valid?("castle")
    assert(Archsight::Resources::Facility.annotations.any? { |a| a.key == "facility/stage" })
    assert(Archsight::Resources::Facility.annotations.any? { |a| a.key == "architecture/aliases" })
    assert_equal %w[location/city location/country], Archsight::Resources::Location.annotations.map(&:key).grep(%r{\Alocation/}).sort
    assert Archsight::Resources::Equipment.annotations.find { |a| a.key == "equipment/type" }.valid?("rack")
  end

  # --- locatedAt, every source to its target ---

  def test_each_source_kind_can_be_located_at_a_facility
    with_db do |db|
      hall = db.instance_by_kind("Facility", "Facility:HallA")

      [["Equipment", "Equipment:Rack01"], ["TechnologyNode", "Node:Web01"],
       ["TechnologySystemSoftware", "Software:Cluster"], ["TechnologyService", "Service:Orders"]].each do |kind, name|
        assert_includes db.instance_by_kind(kind, name).relations(:locatedAt, :facilities), hall, kind
      end
    end
  end

  def test_a_facility_is_located_at_a_location
    with_db do |db|
      campus = db.instance_by_kind("Facility", "Facility:Campus")

      assert_equal ["Location:Germany"], campus.relations(:locatedAt, :locations).map(&:name)
    end
  end

  def test_located_at_with_many_targets_is_one_element
    with_db do |db|
      service = db.instance_by_kind("TechnologyService", "Service:Orders")

      assert_equal %w[Facility:HallA Facility:HallB], service.relations(:locatedAt, :facilities).map(&:name)
      assert_equal 1, db.instances_by_kind("TechnologyService").length
    end
  end

  def test_a_facility_is_served_by_its_operator
    with_db do |db|
      campus = db.instance_by_kind("Facility", "Facility:Campus")

      assert_equal ["Team:Ops"], campus.relations(:servedBy, :businessActors).map(&:name)
    end
  end

  # --- nesting ---

  def test_facilities_nest_with_composed_of
    with_db do |db|
      campus = db.instance_by_kind("Facility", "Facility:Campus")
      hall = db.instance_by_kind("Facility", "Facility:HallA")

      assert_equal %w[Facility:HallA Facility:HallB], campus.relations(:composedOf, :facilities).map(&:name)
      assert_equal [campus], hall.references_grouped.dig("Facility", :composedOf)
    end
  end

  def test_composed_of_cycles_are_reported
    errors = lint(RESOURCES + extra("Facility", "Facility:HallA", "composedOf:\n  facilities:\n    - Facility:Campus"))

    assert_predicate errors.grep(/relation cycle.*composedOf/), :any?
  end

  # --- incoming: what is located here, grouped by kind ---

  def test_a_facility_lists_what_is_located_there_grouped_by_kind
    with_db do |db|
      grouped = db.instance_by_kind("Facility", "Facility:HallA").references_grouped

      assert_equal %w[Equipment:Rack01], grouped.dig("Equipment", :locatedAt).map(&:name)
      assert_equal %w[Node:Web01], grouped.dig("TechnologyNode", :locatedAt).map(&:name)
      assert_equal %w[Software:Cluster], grouped.dig("TechnologySystemSoftware", :locatedAt).map(&:name)
      assert_equal %w[Service:Orders], grouped.dig("TechnologyService", :locatedAt).map(&:name)
    end
  end

  def test_a_location_lists_the_facilities_located_there
    with_db do |db|
      grouped = db.instance_by_kind("Location", "Location:Germany").references_grouped

      assert_equal %w[Facility:Campus], grouped.dig("Facility", :locatedAt).map(&:name)
    end
  end

  def test_the_instance_api_returns_the_incoming_references
    use_examples
    get "/api/v1/kinds/Facility/instances/Facility:Frankfurt:HallA"

    assert_predicate last_response, :ok?
    references = JSON.parse(last_response.body)["references"]

    assert_includes references.dig("TechnologySystemSoftware", "locatedAt"), "Tech:Puma:Cluster"
    assert_includes references.dig("Equipment", "locatedAt"), "Equipment:Frankfurt:HallA:Rack01"
  end

  # --- wrong targets ---

  def test_a_located_at_target_that_is_not_a_facility_is_rejected
    yaml = RESOURCES + extra("TechnologyService", "Service:Wrong", "locatedAt:\n  facilities:\n    - Node:Web01")

    assert_includes load_error(yaml), "Node:Web01 is not defined as kind"
  end

  def test_a_service_cannot_be_located_at_a_location_directly
    yaml = RESOURCES + extra("TechnologyService", "Service:Wrong", "locatedAt:\n  locations:\n    - Location:Germany")

    assert_match(%r{unknown verb locatedAt / kind locations}, load_error(yaml))
  end

  def test_a_facility_cannot_be_located_at_a_facility
    yaml = RESOURCES + extra("Facility", "Facility:Wrong", "locatedAt:\n  facilities:\n    - Facility:HallA")

    assert_match(%r{unknown verb locatedAt / kind facilities}, load_error(yaml))
  end

  def test_archsight_lint_fails_for_a_wrong_located_at_target
    yaml = RESOURCES + extra("Equipment", "Equipment:Wrong", "locatedAt:\n  facilities:\n    - Location:Germany")
    original = Archsight.resources_dir
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      cli = Archsight::CLI.new
      cli.options = { resources: dir }
      out, = capture_io { assert_raises(SystemExit) { cli.lint } }

      assert_includes out, "Location:Germany is not defined as kind"
    end
  ensure
    Archsight.resources_dir = original
  end

  # --- queries from the issue ---

  def test_query_all_technology_services_in_a_facility
    with_db do |db|
      query = Archsight::Query::Query.new('TechnologyService: -> "Facility:HallA"')

      assert_equal %w[Service:Orders], query.filter(db).map(&:name)
    end
  end

  def test_query_facilities_that_host_a_service
    with_db do |db|
      query = Archsight::Query::Query.new('Facility: <- "Service:Orders"')

      assert_equal %w[Facility:HallA Facility:HallB], query.filter(db).map(&:name).sort
    end
  end

  # --- the example ---

  def test_the_examples_model_a_site_and_lint_clean
    db = Archsight::Database.new(EXAMPLES, verbose: false, compute_annotations: false)
    db.reload!

    assert_empty Archsight::Linter.new(db).validate
    cluster = db.instance_by_kind("TechnologySystemSoftware", "Tech:Puma:Cluster")

    assert_equal 3, cluster.relations(:locatedAt, :facilities).length
  end
end
