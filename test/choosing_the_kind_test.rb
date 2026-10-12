# frozen_string_literal: true

require_relative "test_helper"

# The "Choosing the Kind" guide and its example chain in examples/archsight
class ChoosingTheKindTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  KIND_FILES = %w[strategy_capability business_product application_service application_component].freeze

  def setup
    @db = Archsight::Database.new(File.join(ROOT, "examples/archsight"), verbose: false, compute_annotations: false)
    @db.reload!
  end

  def targets(kind, name, verb, key)
    @db.instance_by_kind(kind, name).relations(verb, key).map(&:name)
  end

  def test_example_chain_loads_and_is_linked_bottom_to_top
    assert_equal ["Payment Processing"], targets("BusinessProduct", "Online Checkout", :realizes, :strategyCapabilities)
    assert_equal ["Payment Authorization"], targets("BusinessProduct", "Online Checkout", :servedBy, :applicationServices)
    assert_equal ["Payments:API"], targets("ApplicationService", "Payment Authorization", :realizedThrough, :applicationComponents)
    assert_equal ["Repo:payments-api"], targets("ApplicationComponent", "Payments:API", :realizedThrough, :technologyArtifacts)
  end

  def test_example_chain_is_clean
    assert_empty Archsight::Linter.new(@db).validate
  end

  def test_guide_has_the_section_with_table_questions_rules_and_anti_patterns
    guide = File.read(File.join(ROOT, "docs/modeling.md"))
    section = guide[/^## Choosing the Kind\n.*?(?=^## )/m]

    refute_nil section
    assert_operator guide.index("## Choosing the Kind"), :>, guide.index("## Direction of Relations")
    assert_operator guide.index("## Choosing the Kind"), :<, guide.index("## Identity and Links")
    assert_includes section, "| Kind | Question | Test | Name |"
    assert_equal 8, section.scan(/^\d\. Is it|^\d\. Does the same/).size
    assert_equal 8, section[/\*\*Rules\*\*(.*?)\*\*Example chain/m, 1].scan(/^\d\. /).size
    assert_includes section, "**Anti-patterns**"
  end

  def test_guide_has_no_duplicate_row_and_no_upward_example
    guide = File.read(File.join(ROOT, "docs/modeling.md"))

    assert_equal 1, guide.scan("| TechnologyArtifact |").size
    refute_includes guide, "ManagedKubernetes"
  end

  def test_other_docs_link_the_section
    assert_includes File.read(File.join(ROOT, "docs/togaf.md")), "modeling.md#choosing-the-kind"
    assert_includes File.read(File.join(ROOT, "docs/archimate.md")), "modeling.md#choosing-the-kind"
  end

  def test_kind_descriptions_carry_question_test_and_name
    KIND_FILES.each do |file|
      source = File.read(File.join(ROOT, "lib/archsight/resources/#{file}.rb"))

      assert_includes source, "**Question:**", file
      assert_includes source, "**Test:**", file
      assert_includes source, "**Name:**", file
    end
    refute_includes File.read(File.join(ROOT, "lib/archsight/resources/application_service.rb")), "Complete product offerings"
  end

  def test_no_two_kinds_share_an_example
    examples = {
      "Payment Processing" => "strategy_capability", "Online Checkout" => "business_product",
      "Payment Authorization" => "application_service", "Payments:API" => "application_component"
    }
    files = KIND_FILES.to_h { |f| [f, File.read(File.join(ROOT, "lib/archsight/resources/#{f}.rb"))] }
    examples.each do |example, owner|
      files.each { |file, source| refute_includes source, example, "#{example} in #{file}" unless file == owner }
    end
  end
end
