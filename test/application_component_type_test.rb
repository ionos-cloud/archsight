# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class ApplicationComponentTypeTest < Minitest::Test
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Lib:Shared
      annotations:
        component/type: library
        architecture/tags: ecosystem:go,packaging:go-module
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: App:Api
      annotations:
        component/type: executable
        component/role: service
        architecture/tags: ecosystem:go
        component/entrypoints: cmd/api,cmd/worker
    spec:
      dependsOn:
        applicationComponents:
          - Lib:Shared
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: App:Worker
      annotations:
        component/type: executable
        component/role: job
    spec:
      dependsOn:
        applicationComponents:
          - Lib:Shared
  YAML

  def with_db(yaml = RESOURCES)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), yaml)
      db = Archsight::Database.new(dir, verbose: false)
      db.reload!
      yield db
    end
  end

  def annotation(key)
    Archsight::Resources::ApplicationComponent.annotations.find { |a| a.key == key }
  end

  def test_type_and_role_only_accept_known_values
    assert annotation("component/type").valid?("module")
    assert annotation("component/type").valid?("frontend")
    refute annotation("component/type").valid?("package")
    assert annotation("component/role").valid?("operator")
    refute annotation("component/role").valid?("daemon")
  end

  def test_there_is_one_tag_annotation_and_it_takes_machine_tags
    keys = Archsight::Resources::ApplicationComponent.annotations.map(&:key)

    assert_includes keys, "architecture/tags"
    refute_includes keys, "component/tags"
    assert annotation("architecture/tags").valid?("rest,ecosystem:go")
  end

  def test_entrypoints_are_a_list_but_not_a_sidebar_filter
    filterable = Archsight::Resources::ApplicationComponent.filterable_annotations.map(&:key)

    assert_predicate annotation("component/entrypoints"), :list?
    refute_includes filterable, "component/entrypoints"
    assert_includes filterable, "architecture/tags"
  end

  def test_summary_annotations_stay_within_the_limit
    summary = Archsight::Resources::ApplicationComponent.summary_annotations

    assert_operator summary.length, :<=, 3
    refute_includes summary.map(&:key), "component/type"
  end

  def test_dependents_count_the_components_that_depend_on_a_component
    with_db do |db|
      library = db.instance_by_kind("ApplicationComponent", "Lib:Shared")
      app = db.instance_by_kind("ApplicationComponent", "App:Api")

      assert_equal 2, library.computed_annotation_value("component/dependents").to_i
      assert_equal 0, app.computed_annotation_value("component/dependents").to_i
    end
  end

  def test_components_can_be_found_by_type_and_by_entry_point
    with_db do |db|
      by_type = db.query('ApplicationComponent: component/type == "library"').map(&:name)
      by_tag = db.query('ApplicationComponent: component/entrypoints == "cmd/api"').map(&:name)

      assert_equal ["Lib:Shared"], by_type
      assert_equal ["App:Api"], by_tag
    end
  end
end
