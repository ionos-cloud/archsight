# frozen_string_literal: true

require_relative "pdf_fixture"

class PdfThemeTest < Minitest::Test
  include PdfFixture

  def setup = build_resources
  def teardown = cleanup_resources

  def test_without_a_template_the_built_in_look_is_used
    theme = Archsight::Pdf::Theme.new

    assert_equal Archsight::Pdf::Theme::COLORS[:primary], theme.colors[:primary]
    assert_nil theme.logo
    assert_equal "en", theme.lang
  end

  def test_default_template_is_used_when_none_is_requested
    theme = Archsight::Pdf::Theme.for(@db)

    assert_equal "#112233", theme.colors[:primary]
    assert_equal "Internal", theme.classification
  end

  def test_template_is_found_by_name_with_or_without_prefix
    assert_equal "#aa0000", Archsight::Pdf::Theme.for(@db, "brand").colors[:primary]
    assert_equal "#aa0000", Archsight::Pdf::Theme.for(@db, "PDF:brand").colors[:primary]
    assert_equal "#aa0000", Archsight::Pdf::Theme.for(@db, "Config:PDF:brand").colors[:primary]
    assert_equal "#aa0000", Archsight::Pdf::Theme.for(@db, "config:pdf:BRAND").colors[:primary]
  end

  def test_configs_of_another_type_or_without_one_are_never_used
    File.write(File.join(@dir, "other.yaml"), <<~YAML)
      ---
      apiVersion: architecture/v1alpha1
      kind: Config
      metadata:
        name: Config:Mail:default
        annotations:
          config/type: mail
          pdf/color-primary: "#00ff00"
      spec: {}
      ---
      apiVersion: architecture/v1alpha1
      kind: Config
      metadata:
        name: Config:Untyped
        annotations:
          pdf/color-primary: "#0000ff"
      spec: {}
    YAML
    @db.reload!

    assert_equal "#112233", Archsight::Pdf::Theme.for(@db).colors[:primary]
    assert_equal Archsight::Pdf::Theme::COLORS[:primary], Archsight::Pdf::Theme.for(@db, "Untyped").colors[:primary]
  end

  def test_unknown_template_falls_back_to_the_built_in_look
    theme = Archsight::Pdf::Theme.for(@db, "nope")

    assert_equal Archsight::Pdf::Theme::COLORS[:primary], theme.colors[:primary]
  end

  def test_invalid_values_are_replaced_by_defaults
    theme = Archsight::Pdf::Theme.for(@db, "brand")

    assert_equal Archsight::Pdf::Theme::COLORS[:accent], theme.colors[:accent]
  end

  def test_logo_is_resolved_inside_the_resources_dir_only
    template = Struct.new(:name, :annotations).new("T", { "pdf/logo" => "../outside.svg", "pdf/font-dir" => "../.." })
    theme = Archsight::Pdf::Theme.new(template, resources_dir: @dir)

    assert_nil theme.logo
    assert_nil theme.font_dir
    assert_equal File.realpath(File.join(@dir, "img", "logo.svg")), Archsight::Pdf::Theme.for(@db, "brand").logo
  end

  def test_typst_source_escapes_text_and_lists_only_checked_values
    source = Archsight::Pdf::Theme.for(@db, "brand").to_typst(logo: "logo.svg", logo_light: "logo.svg")

    assert_includes source, 'primary: rgb("#aa0000")'
    assert_includes source, 'footer-text: "Footer \\"quoted\\""'
    assert_includes source, 'header-meta: ("id", "version",)'
    assert_includes source, 'logo: "logo.svg"'
    assert_includes source, 'lang: "de"'
  end

  def test_heading_breaks_are_checked_and_listed_in_the_typst_source
    assert_equal [], Archsight::Pdf::Theme.new.break_before
    assert_includes Archsight::Pdf::Theme.new.to_typst, "break-before: (), keep-space: ()"

    File.write(File.join(@dir, "breaks.yaml"), <<~YAML)
      ---
      apiVersion: architecture/v1alpha1
      kind: Config
      metadata:
        name: Config:PDF:breaks
        annotations:
          config/type: pdf
          pdf/break-before: "2, 1, x, 9, 1"
          pdf/keep-space: "2:30%, 3:20, 1:50%, 4:200%, nonsense"
      spec: {}
    YAML
    @db.reload!
    theme = Archsight::Pdf::Theme.for(@db, "breaks")

    assert_equal [1, 2], theme.break_before
    assert_equal [[3, 20]], theme.keep_space # 2 and 1 always break, 4 is out of range
    assert_includes theme.to_typst, "break-before: (1, 2,), keep-space: ((3, 20),)"
  end
end
