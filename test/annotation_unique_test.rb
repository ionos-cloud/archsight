# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Aliases: unique identifiers (architecture/aliases) that are not tags, not facets, and found by the name shortcut
class AnnotationUniqueTest < Minitest::Test
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Foo
      annotations:
        architecture/aliases: ITGS:A001, C5:COS-07
        architecture/tags: billing
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Bar
      annotations:
        architecture/aliases: ITGS:A002
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Plain
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: Elsewhere
      annotations:
        architecture/aliases: ITGS:A001
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

  def lint(db)
    Archsight::Linter.new(db).validate
  end

  def aliases
    Archsight::Resources::ApplicationService.annotations.find { |a| a.key == "architecture/aliases" }
  end

  def test_aliases_are_unique_identifiers_and_not_facets
    assert_predicate aliases, :unique?
    assert_predicate aliases, :list?
    assert_equal :identifier, aliases.format
    refute_includes Archsight::Resources::ApplicationService.filterable_annotations.map(&:key), "architecture/aliases"
  end

  def test_tags_are_not_unique
    tags = Archsight::Resources::ApplicationService.annotations.find { |a| a.key == "architecture/tags" }

    refute_predicate tags, :unique?
    assert_equal :tag_list, tags.format
  end

  def test_the_same_alias_in_different_kinds_is_fine
    with_db { |db| assert_empty lint(db) }
  end

  def test_two_resources_of_a_kind_must_not_share_an_alias
    yaml = RESOURCES.sub("ITGS:A002", "ITGS:A001")

    with_db(yaml) do |db|
      errors = lint(db)

      assert_equal 1, errors.length
      assert_match(%r{ApplicationService 'Bar': architecture/aliases 'ITGS:A001' is already used by 'Foo' \(}, errors.first)
    end
  end

  def test_an_alias_repeated_in_one_resource_is_ignored
    yaml = RESOURCES.sub("ITGS:A001, C5:COS-07", "ITGS:A001, ITGS:A001")

    with_db(yaml) { |db| assert_empty lint(db) }
  end

  def test_the_name_shortcut_finds_a_resource_by_alias
    with_db do |db|
      assert_equal ["Foo"], db.query("COS-07").map(&:name)
      assert_equal ["Foo"], db.query('ApplicationService: name == "C5:COS-07"').map(&:name)
      assert_equal %w[Bar Foo], db.query('name in ("ITGS:A001", "ITGS:A002") & kind == "ApplicationService"').map(&:name).sort
      assert_equal ["Foo"], db.query('ApplicationService: architecture/aliases == "ITGS:A001"').map(&:name)
    end
  end

  def test_name_not_equal_also_considers_aliases
    with_db do |db|
      names = db.query('ApplicationService: name != "ITGS:A001"').map(&:name)

      refute_includes names, "Foo"
      assert_includes names, "Bar"
    end
  end

  def test_documents_of_one_resource_add_to_its_list_annotations
    yaml = <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: ApplicationService
      metadata:
        name: Foo
        annotations:
          architecture/aliases: ITGS:A001
          architecture/tags: billing, eu
      spec: {}
      ---
      apiVersion: architecture/v1alpha1
      kind: ApplicationService
      metadata:
        name: Foo
        annotations:
          architecture/aliases: C5:COS-07, ITGS:A001
          architecture/tags: payments
          architecture/documentation: https://docs.example.com/foo
      spec: {}
    YAML

    with_db(yaml) do |db|
      annotations = db.instance_by_kind("ApplicationService", "Foo").annotations

      assert_equal "ITGS:A001,C5:COS-07", annotations["architecture/aliases"]
      assert_equal "billing,eu,payments", annotations["architecture/tags"]
      assert_equal "https://docs.example.com/foo", annotations["architecture/documentation"]
    end
  end

  def test_other_annotations_still_replace_each_other_on_merge
    yaml = <<~YAML
      ---
      apiVersion: architecture/v1alpha1
      kind: ApplicationService
      metadata:
        name: Foo
        annotations:
          architecture/abbr: OLD
      spec: {}
      ---
      apiVersion: architecture/v1alpha1
      kind: ApplicationService
      metadata:
        name: Foo
        annotations:
          architecture/abbr: NEW
      spec: {}
    YAML

    with_db(yaml) { |db| assert_equal "NEW", db.instance_by_kind("ApplicationService", "Foo").annotations["architecture/abbr"] }
  end
end
