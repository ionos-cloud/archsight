# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Names contain colons (Archsight:CLI, ITGS:A001): typing one finds it instead of reading it as a kind and a condition
class QueryNamesTest < Minitest::Test
  RESOURCES = <<~YAML
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Archsight:CLI
      annotations:
        architecture/aliases: ITGS:A001, C5:COS-07
        architecture/abbr: CLI
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Archsight:Web
      annotations:
        architecture/aliases: ITGS:A1.4
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: TechnologyService
    metadata:
      name: Archsight:CLI
    spec: {}
  YAML

  def with_db
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "test.yaml"), RESOURCES)
      db = Archsight::Database.new(dir, verbose: false, compute_annotations: false)
      db.reload!
      yield db
    end
  end

  def found(db, query)
    db.query(query).map { |i| "#{i.klass}/#{i.name}" }.sort
  end

  def test_a_name_with_colons_finds_the_resource
    with_db do |db|
      assert_equal %w[ApplicationService/Archsight:CLI TechnologyService/Archsight:CLI], found(db, "Archsight:CLI")
    end
  end

  def test_an_alias_with_a_colon_finds_the_resource
    with_db do |db|
      assert_equal ["ApplicationService/Archsight:CLI"], found(db, "ITGS:A001")
      assert_equal ["ApplicationService/Archsight:CLI"], found(db, "C5:COS-07")
      assert_equal ["ApplicationService/Archsight:Web"], found(db, "ITGS:A1.4")
    end
  end

  def test_a_kind_followed_by_a_name_with_colons
    with_db do |db|
      assert_equal ["ApplicationService/Archsight:CLI"], found(db, "ApplicationService:Archsight:CLI")
      assert_equal ["TechnologyService/Archsight:CLI"], found(db, "TechnologyService:Archsight:CLI")
      assert_equal ["ApplicationService/Archsight:CLI"], found(db, "ApplicationService:ITGS:A001")
    end
  end

  def test_a_kind_with_a_space_is_still_a_kind_filter
    with_db do |db|
      assert_equal %w[ApplicationService/Archsight:CLI ApplicationService/Archsight:Web], found(db, "ApplicationService:")
      assert_equal ["ApplicationService/Archsight:CLI"], found(db, "ApplicationService: CLI")
      assert_equal ["ApplicationService/Archsight:CLI"], found(db, 'ApplicationService: architecture/abbr == "CLI"')
    end
  end

  def test_a_name_search_can_be_combined
    with_db do |db|
      assert_equal ["ApplicationService/Archsight:CLI"], found(db, "ITGS:A001 & kind == \"ApplicationService\"")
      assert_equal %w[ApplicationService/Archsight:CLI ApplicationService/Archsight:Web], found(db, "ITGS:A001 | ITGS:A1.4")
    end
  end

  def test_an_unknown_prefix_with_a_condition_keeps_its_old_meaning
    with_db do |db|
      assert_empty found(db, "Unknown: architecture/abbr == \"CLI\"")
      assert_empty found(db, "Unknown:abbr == \"CLI\"")
      assert_empty found(db, "Unknown:")
    end
  end

  def test_a_name_that_matches_nothing_is_empty_not_an_error
    with_db do |db|
      assert_empty found(db, "Nothing:Here")
      assert_empty found(db, "ITGS:A999")
    end
  end

  def test_a_name_with_colons_can_follow_a_condition
    with_db do |db|
      assert_equal ["ApplicationService/Archsight:CLI"], found(db, "ApplicationService: architecture/abbr == \"CLI\" & ITGS:A001")
    end
  end
end
