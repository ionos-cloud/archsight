# frozen_string_literal: true

require_relative "pdf_fixture"
require "archsight/pdf/resource_sheet"

class PdfResourceSheetTest < Minitest::Test
  include PdfFixture

  RESOURCES = <<~'YAML'
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Core:Billing
      annotations:
        architecture/description: Bills.
        architecture/tags: one,two
        component/role: service
        lifecycle/status: active
        lifecycle/reason: "Line one\nLine two"
    spec:
      dependsOn:
        applicationComponents:
          - Core:Shipping
          - Core:Tax
          - Core:Rates
          - Core:Ledger
      exposes:
        applicationInterfaces:
          - Public:Billing:API
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Core:Shipping
    spec:
      dependsOn:
        applicationComponents:
          - Core:Billing
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Core:Tax
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Core:Rates
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Core:Ledger
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationComponent
    metadata:
      name: Core:Lonely
    spec: {}
    ---
    apiVersion: architecture/v1alpha1
    kind: ApplicationInterface
    metadata:
      name: Public:Billing:API
    spec: {}
  YAML

  def setup
    build_resources
    File.write(File.join(@dir, "sheet.yaml"), RESOURCES)
    @db.reload!
  end

  def teardown = cleanup_resources

  def sheet(name)
    Archsight::Pdf::ResourceSheet.new(@db.instance_by_kind("ApplicationComponent", name), markdown: ->(text) { "MD(#{text.strip})" })
  end

  def test_humanize_splits_camel_case
    assert_equal "depends on", Archsight::Pdf::ResourceSheet.humanize("dependsOn")
    assert_equal "realized through", Archsight::Pdf::ResourceSheet.humanize(:realizedThrough)
    assert_equal "exposes", Archsight::Pdf::ResourceSheet.humanize("exposes")
  end

  def test_properties_are_a_label_and_value_table_without_the_text_annotations
    out = sheet("Core:Billing").properties.join("\n")

    assert_includes out, '#heading(level: 1)[#"Properties"]'
    assert_includes out, '#text(fill: theme.muted)[#"Component Role"]'
    assert_includes out, '[#"service"]'
    refute_includes out, "Bills."          # the description is the introduction, not a property
    refute_includes out, '#"one, two"'     # nor are the tags
  end

  def test_annotations_of_one_namespace_stay_together_with_a_gap_between_namespaces
    out = sheet("Core:Billing").properties.first

    assert_includes out, "table.cell(colspan: 2, stroke: none"
    assert_operator out.index('"Component Role"'), :<, out.index('"Lifecycle"')
    assert_operator out.index('"Lifecycle"'), :<, out.index('"Total Git Repositories"')
  end

  def test_a_markdown_value_gets_its_own_section_instead_of_vanishing
    parts = sheet("Core:Billing").properties

    assert_equal 2, parts.size
    assert_includes parts.last, '#heading(level: 2)[#"Reason"]'
    assert_includes parts.last, "MD(Line one\nLine two)"
  end

  def test_a_resource_without_relations_has_no_relations_section
    assert_empty sheet("Core:Lonely").relations
    refute_empty sheet("Core:Tax").relations # Core:Billing depends on it
  end

  def test_outgoing_relations_say_the_relation_once_and_flow_the_names_in_columns
    out = sheet("Core:Billing").relations.join("\n")

    assert_includes out, '#heading(level: 2)[#"Outgoing"]'
    assert_includes out, 'table.cell(rowspan: 1)[#text(weight: "semibold")[#"depends on"]]'
    assert_includes out, "#grid(columns: (1fr, 1fr,)" # four names: two columns
    assert_includes out, '#"Core:​Ledger"' # a break is allowed after the colon
    assert_includes out, '#"exposes"'
  end

  def test_incoming_relations_are_shown_like_the_outgoing_ones
    out = sheet("Core:Billing").relations.join("\n")

    assert_includes out, '#heading(level: 2)[#"Incoming"]'
    assert_includes out, "the relation is read from their side"
    assert_includes out, '#"Core:​Shipping"'
  end

  def test_only_incoming_still_shows_the_relations_section
    parts = sheet("Core:Tax").relations

    assert_includes parts.first, '#"Relations"'
    refute(parts.any? { |part| part.include?('"Outgoing"') })
    assert(parts.any? { |part| part.include?('"Incoming"') })
  end

  def test_the_document_uses_the_sheet_and_compiles
    skip "typst is not installed" unless typst?

    doc = Archsight::Pdf.document(@db, @db.instance_by_kind("ApplicationComponent", "Core:Billing"), resources_dir: @dir)

    assert_includes doc.files["main.typ"], '#"Incoming"'
    assert Archsight::Pdf.compile(doc).start_with?("%PDF")
  end
end
