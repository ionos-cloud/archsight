# frozen_string_literal: true

require_relative "test_helper"

class ViewTableTest < Minitest::Test
  DATA = <<~YAML
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Service10
      annotations:
        backup/mode: none
        activity/commits: "7"
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: Service2
      annotations:
        backup/mode: daily
        activity/commits: "30"
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationService
    metadata:
      name: service3
      annotations:
        backup/mode: none
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Component
      annotations:
        backup/mode: none
    ---
    apiVersion: architecture/v1alpha1
    kind: View
    metadata:
      name: Backup gaps
      annotations:
        view/query: 'ApplicationService: backup/mode == "none"'
        view/fields: name, backup/mode
        view/sort: -name
        view/type: list:name
  YAML

  def setup
    @dir = Dir.mktmpdir
    File.write(File.join(@dir, "data.yaml"), DATA)
    @db = Archsight::Database.new(@dir, compute_annotations: false).tap(&:reload!)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def table(**) = Archsight::ViewTable.build(@db, query: "ApplicationService:", **)

  def texts(table, column = 0) = table.rows.map { |row| row[column].text }

  def test_name_and_kind_columns_and_rows_sorted_by_name_by_default
    result = table

    assert_equal %w[Name Kind], result.columns
    assert_equal %w[Service10 Service2 service3], texts(result)
    assert_equal ["ApplicationService"], texts(result, 1).uniq
    assert_equal 3, result.total
    assert_equal 0, result.cut
  end

  def test_list_name_has_no_kind_column
    assert_equal ["Name"], table(show_kind: false).columns
  end

  def test_field_columns_with_titles_and_values_and_identity_fields_left_out
    result = table(fields: ["name", "backup/mode", "activity/commits", "kind"], show_kind: false)

    assert_equal ["Name", "Backup mode", "Activity commits"], result.columns
    rows = result.rows.map { |row| row.map(&:text) }

    assert_equal [%w[Service10 none 7], %w[Service2 daily 30], ["service3", "none", ""]], rows
  end

  def test_column_title_follows_the_web_ui
    titles = { "scc/language/Go/loc" => "Go loc", "activity/createdAt" => "Activity created At", "status" => "Status", "a/b" => "A b" }

    titles.each { |key, title| assert_equal title, Archsight::ViewTable.column_title(key), key }
  end

  def test_sort_descending_ascending_numeric_and_by_annotation
    assert_equal %w[Service10 service3 Service2], texts(table(sort: ["-name"]))
    assert_equal %w[Service2 service3 Service10], texts(table(sort: ["name"]))
    assert_equal %w[Service2 Service10 service3], texts(table(sort: ["-activity/commits"]))
    assert_equal %w[Service2 service3 Service10], texts(table(sort: %w[backup/mode name]))
  end

  def test_limit_cuts_rows_but_keeps_the_total
    result = table(limit: 2)

    assert_equal 2, result.rows.length
    assert_equal 3, result.total
    assert_equal 1, result.cut
  end

  def test_name_cells_carry_the_resource
    cell = table.rows.first.first

    assert_equal "Service10", cell.resources.first.name
  end

  def test_bad_query_raises
    assert_raises(Archsight::Query::QueryError) { table_with_query("ApplicationService: (((") }
  end

  def table_with_query(query) = Archsight::ViewTable.build(@db, query: query)

  def test_from_view_reads_the_view_annotations
    view = @db.instances_by_kind("View")["Backup gaps"]
    result = Archsight::ViewTable.from_view(@db, view)

    assert_equal "Backup gaps", result.title
    assert_equal ["Name", "Backup mode"], result.columns
    assert_equal %w[Service10 service3], texts(result)
  end

  def test_from_view_without_a_query_raises
    view = Archsight::Resources::View.new({ "apiVersion" => "architecture/v1alpha1", "kind" => "View", "metadata" => { "name" => "Empty" } }, Archsight::LineReference.new("t", 0))

    assert_raises(Archsight::Helpers::ViewBlocks::Error) { Archsight::ViewTable.from_view(@db, view) }
  end

  def test_from_block_reads_a_view_block
    source = "kind: View\nmetadata:\n  name: T\n  annotations:\n    view/query: 'ApplicationComponent:'\n    view/type: list:name\n"
    result = Archsight::ViewTable.from_block(@db, source)

    assert_equal "T", result.title
    assert_equal ["Component"], texts(result)
  end
end
