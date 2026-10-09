# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "open3"
require "rbconfig"
require "rack/test"
require "archsight/editor"
require "archsight/web/application"
require "json"

# BusinessRequirement and BusinessConstraint were renamed to MotivationRequirement and MotivationConstraint (with
# their relation keys). The old names still load, query and link, and `archsight lint` reports them as deprecated.
class RenamedKindsTest < Minitest::Test
  # A resource set written entirely with the old names
  OLD = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessRequirement
    metadata:
      name: Requirement:Backup
      annotations:
        requirement/priority: must
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: BusinessConstraint
    metadata:
      name: Constraint:Budget
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Service:Backup
    spec:
      realizes:
        businessRequirements:
          - Requirement:Backup
        businessConstraints:
          - Constraint:Budget
  YAML

  def with_db(yaml = OLD, **)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, **)
      db.reload!
      yield db
    end
  end

  def test_old_kind_names_resolve_to_the_new_classes
    assert_equal Archsight::Resources::MotivationRequirement, Archsight::Resources["BusinessRequirement"]
    assert_equal Archsight::Resources::MotivationConstraint, Archsight::Resources["BusinessConstraint"]
    assert_equal "MotivationRequirement", Archsight::Resources.canonical("BusinessRequirement")
    assert_equal "MotivationRequirement", Archsight::Resources.canonical("MotivationRequirement")
    assert_equal "BusinessProcess", Archsight::Resources.canonical("BusinessProcess")
  end

  def test_every_kind_is_listed_once_under_its_new_name
    kinds = Enumerator.new { |names| Archsight::Resources.each { |name| names << name } }.to_a

    assert_includes kinds, "MotivationRequirement"
    assert_includes kinds, "MotivationConstraint"
    refute_includes kinds, "BusinessRequirement"
    refute_includes kinds, "BusinessConstraint"
    assert_equal kinds.uniq, kinds
  end

  def test_the_kinds_are_in_the_motivation_layer
    assert_equal "motivation", Archsight::Resources::MotivationRequirement.layer
    assert_equal "motivation", Archsight::Resources::MotivationConstraint.layer
  end

  def test_old_documents_load_as_the_new_kinds
    with_db do |db|
      requirement = db.instance_by_kind("MotivationRequirement", "Requirement:Backup")

      assert_equal "MotivationRequirement", requirement.klass
      assert_equal "MotivationRequirement", requirement.kind
      assert_equal "Constraint:Budget", db.instance_by_kind("BusinessConstraint", "Constraint:Budget").name
    end
  end

  def test_old_relation_keys_are_normalised_and_resolve
    with_db do |db|
      service = db.instance_by_kind("ApplicationService", "Service:Backup")

      assert_equal ["Requirement:Backup"], service.relations(:realizes, :motivationRequirements).map(&:name)
      assert_equal ["Constraint:Budget"], service.relations(:realizes, :motivationConstraints).map(&:name)
      refute service.spec["realizes"].key?("businessRequirements")
      requirement = db.instance_by_kind("MotivationRequirement", "Requirement:Backup")

      assert_equal ["Service:Backup"], requirement.references_grouped.dig("ApplicationService", :realizes)&.map(&:name)
    end
  end

  def test_old_and_new_spellings_of_one_resource_merge
    yaml = OLD + <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: MotivationRequirement
      metadata:
        name: Requirement:Backup
        annotations:
          requirement/type: compliance
      spec: {}
    YAML
    with_db(yaml) do |db|
      requirements = db.instances_by_kind("MotivationRequirement")

      assert_equal ["Requirement:Backup"], requirements.keys
      annotations = requirements["Requirement:Backup"].annotations

      assert_equal "must", annotations["requirement/priority"]
      assert_equal "compliance", annotations["requirement/type"]
    end
  end

  def test_old_and_new_relation_keys_in_one_document_are_combined
    yaml = OLD.sub("      realizes:\n", "      realizes:\n        motivationRequirements:\n          - Requirement:Backup\n")
    with_db(yaml) do |db|
      service = db.instance_by_kind("ApplicationService", "Service:Backup")

      assert_equal ["Requirement:Backup"], service.relations(:realizes, :motivationRequirements).map(&:name)
    end
  end

  def test_the_only_kinds_filter_accepts_either_name
    with_db(OLD, only_kinds: %w[BusinessRequirement], verify: false) do |db|
      assert_equal ["Requirement:Backup"], db.instances_by_kind("MotivationRequirement").keys
      assert_empty db.instances_by_kind("MotivationConstraint")
    end
    with_db(OLD, only_kinds: %w[MotivationConstraint], verify: false) do |db|
      assert_equal ["Constraint:Budget"], db.instances_by_kind("MotivationConstraint").keys
      assert_empty db.instances_by_kind("MotivationRequirement")
    end
  end

  def test_every_use_of_an_old_name_is_a_deprecation
    with_db do |db|
      messages = db.deprecations.map(&:message)

      assert_equal 4, messages.length
      assert(messages.any? { |m| m.include?("kind 'BusinessRequirement' is renamed to 'MotivationRequirement'") })
      assert(messages.any? { |m| m.include?("kind 'BusinessConstraint' is renamed to 'MotivationConstraint'") })
      assert(messages.any? { |m| m.include?("relation key 'businessRequirements' under 'realizes' is renamed to 'motivationRequirements'") })
      assert(messages.any? { |m| m.include?("relation key 'businessConstraints' under 'realizes' is renamed to 'motivationConstraints'") })
      assert(db.deprecations.all? { |d| d.to_s.start_with?(d.ref.to_s) })
    end
  end

  def test_the_new_names_are_not_deprecated
    with_db(OLD.gsub("BusinessRequirement", "MotivationRequirement").gsub("BusinessConstraint", "MotivationConstraint")
               .gsub("businessRequirements", "motivationRequirements").gsub("businessConstraints", "motivationConstraints")) do |db|
      assert_empty db.deprecations
    end
  end

  def test_the_linter_reports_deprecations_as_warnings_not_errors
    with_db do |db|
      linter = Archsight::Linter.new(db)

      assert_empty linter.validate
      assert_equal 4, linter.warnings.length
    end
  end

  def test_queries_with_the_old_kind_name_still_match
    with_db do |db|
      assert_equal ["Requirement:Backup"], db.query('BusinessRequirement: name =~ ".*"').map(&:name)
      assert_equal ["Requirement:Backup"], db.query('kind == "BusinessRequirement"').map(&:name)
      assert_equal %w[Constraint:Budget Requirement:Backup], db.query('kind in ("BusinessRequirement", "BusinessConstraint")').map(&:name).sort
      assert_equal ["Service:Backup"], db.query("ApplicationService: ~> BusinessRequirement").map(&:name)
      assert_equal ["Service:Backup"], db.query("ApplicationService: ~> MotivationRequirement").map(&:name)
    end
  end

  def test_the_editor_writes_the_new_kind
    resource = Archsight::Editor.build_resource(kind: "BusinessRequirement", name: "Requirement:X")

    assert_equal "MotivationRequirement", resource["kind"]
  end

  def test_links_to_a_resource_by_its_old_kind_use_the_new_kind
    with_db do |db|
      resolver = Archsight::Helpers::ResourceResolver.new(db)

      assert_equal %w[MotivationRequirement Requirement:Backup], resolver.find("BusinessRequirement/Requirement:Backup")
      assert_includes resolver.call("BusinessRequirement/Requirement:Backup"), "/kinds/MotivationRequirement/"
    end
  end

  def test_archsight_lint_exits_zero_and_lists_the_deprecations
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), OLD)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e",
                                              %(ARGV.replace(["lint", "-r", #{dir.inspect}]); load "exe/archsight"),
                                              chdir: File.expand_path("..", __dir__))

      assert_predicate status, :success?, stderr
      assert_includes stdout, "Deprecations (4):"
      assert_includes stdout, "kind 'BusinessRequirement' is renamed to 'MotivationRequirement'"
      assert_includes stdout, "All validations passed!"
    end
  end
end

class RenamedKindsAPITest < Minitest::Test
  include Rack::Test::Methods

  def app
    Archsight::Web::Application
  end

  def setup
    Archsight.resources_dir = File.expand_path("../examples/archsight", __dir__)
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
  end

  def json_response
    JSON.parse(last_response.body)
  end

  def test_the_kinds_list_has_the_new_names_once
    get "/api/v1/kinds"
    names = json_response["kinds"].map { |k| k["kind"] }

    assert_includes names, "MotivationRequirement"
    refute_includes names, "BusinessRequirement"
    assert_equal names.uniq, names
    layer = json_response["kinds"].find { |k| k["kind"] == "MotivationRequirement" }["layer"]

    assert_equal "motivation", layer
  end

  def test_an_old_kind_url_still_answers_with_the_new_kind_name
    get "/api/v1/kinds/BusinessRequirement"

    assert_predicate last_response, :ok?
    assert_equal "MotivationRequirement", json_response["kind"]
    refute_empty json_response["instances"]
  end

  def test_the_generated_help_of_an_old_kind_name_is_the_help_of_the_new_kind
    get "/api/v1/docs/resources/business_requirement"

    assert_predicate last_response, :ok?
    assert_includes last_response.body, "MotivationRequirement"
    refute_includes last_response.body, "BusinessRequirement"
  end

  def test_an_old_instance_url_still_answers_with_the_new_kind_name
    get "/api/v1/kinds/BusinessRequirement/instances/Requirement:OpenSource"

    assert_predicate last_response, :ok?
    assert_equal "MotivationRequirement", json_response["kind"]
  end
end
