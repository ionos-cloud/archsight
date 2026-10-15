# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class LifecycleAnnotationTest < Minitest::Test
  KINDS = %w[BusinessProduct ApplicationComponent ApplicationService TechnologyService TechnologyArtifact].freeze

  def resource_yaml(kind, name, annotations = {})
    <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: #{kind}
      metadata:
        name: #{name}
        annotations:
          architecture/description: x
      #{annotations.map { |key, value| "    #{key}: #{value}" }.join("\n")}
      spec: {}
    YAML
  end

  def lint(kind, annotations)
    lint_yaml(resource_yaml(kind, "Thing", annotations))
  end

  def lint_two(annotations)
    lint_yaml(resource_yaml("ApplicationService", "New") + resource_yaml("ApplicationService", "Old", annotations))
  end

  def lint_yaml(yaml)
    with_db(yaml) { |db| Archsight::Linter.new(db).validate }
  end

  def with_db(yaml)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def test_every_state_is_accepted_on_products_components_and_services
    KINDS.each do |kind|
      Archsight::Annotations::Architecture::LIFECYCLE_STATUSES.each do |status|
        assert_empty lint(kind, "lifecycle/status" => status), "#{kind} #{status}"
      end
    end
  end

  def test_planned_comes_before_active
    assert_equal %w[planned active], Archsight::Annotations::Architecture::LIFECYCLE_STATUSES.first(2)
  end

  def test_a_resource_without_a_status_is_active
    with_db(resource_yaml("ApplicationService", "Plain") +
            resource_yaml("ApplicationService", "Next", "lifecycle/status" => "planned", "lifecycle/activeAt" => "2027-01-31")) do |db|
      plain = db.instance_by_kind("ApplicationService", "Plain")
      upcoming = db.instance_by_kind("ApplicationService", "Next")

      assert_equal "active", plain.annotations["lifecycle/status"]
      assert plain.defaulted?("lifecycle/status")
      assert_equal "planned", upcoming.annotations["lifecycle/status"]
      refute upcoming.defaulted?("lifecycle/status")
      assert_equal ["Plain"], Archsight::Query.parse('lifecycle/status == "active"').filter(db).map(&:name)
    end
  end

  def test_the_template_starts_with_the_default
    assert_includes Archsight::Template.generate("ApplicationService"), "lifecycle/status: active"
  end

  def test_unknown_state_is_rejected
    errors = lint("ApplicationComponent", "lifecycle/status" => "retired")

    refute_empty errors.grep(%r{lifecycle/status.*retired})
  end

  def test_dates_are_validated
    assert_empty lint("ApplicationService", "lifecycle/sunsetAt" => "2027-03-31", "lifecycle/endOfLifeAt" => %("2027-12-31T09:30:00Z"))
    refute_empty lint("ApplicationService", "lifecycle/deprecatedAt" => "someday")
  end

  def test_reason_is_a_known_annotation
    assert_empty lint("BusinessProduct", "lifecycle/reason" => "old")
  end

  def test_replaced_by_is_a_resource_reference
    annotation = Archsight::Resources::ApplicationComponent.annotation_matching("lifecycle/replacedBy")

    assert_predicate annotation, :resource?
    assert_equal :resource, Archsight::Resources::ApplicationComponent.annotation_format("lifecycle/replacedBy")
  end

  def test_replaced_by_must_name_an_existing_resource
    assert_empty lint_two("lifecycle/replacedBy" => "New")
    assert_empty lint_two("lifecycle/replacedBy" => "ApplicationService/New")
    refute_empty lint_two("lifecycle/replacedBy" => "Missing").grep(/resource 'Missing' not found/)
    refute_empty lint_two("lifecycle/replacedBy" => "Other/New").grep(/not found/)
  end

  def test_a_bare_name_means_the_same_kind
    yaml = resource_yaml("ApplicationService", "New") + resource_yaml("ApplicationComponent", "Old", "lifecycle/replacedBy" => "New")

    errors = lint_yaml(yaml)

    refute_empty errors.grep(%r{resource 'New' not found \(a name without Kind/ is a ApplicationComponent})
  end

  def test_a_component_can_be_replaced_by_a_service_with_kind
    yaml = resource_yaml("ApplicationService", "New") +
           resource_yaml("ApplicationComponent", "Old", "lifecycle/replacedBy" => "ApplicationService/New")

    assert_empty lint_yaml(yaml)
  end

  def test_replaced_by_rejects_free_text
    errors = lint_two("lifecycle/replacedBy" => %("the new one"))

    refute_empty errors.grep(/Expected a resource name/)
  end
end
