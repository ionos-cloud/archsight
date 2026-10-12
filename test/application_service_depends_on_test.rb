# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

# ApplicationService dependsOn ApplicationService: one service uses another without listing its components
class ApplicationServiceDependsOnTest < Minitest::Test
  def service(name, depends_on = [])
    spec = depends_on.empty? ? "spec: {}" : "spec:\n  dependsOn:\n    applicationServices:\n#{depends_on.map { |d| "      - #{d}" }.join("\n")}"
    "---\napiVersion: architecture/v1alpha1\nkind: ApplicationService\nmetadata:\n  name: #{name}\n#{spec}\n"
  end

  def with_db(yaml)
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

  def test_relation_is_declared_on_the_service
    assert_includes Archsight::Resources::ApplicationService.declared_relations, %i[dependsOn applicationServices ApplicationService]
  end

  def test_a_service_can_depend_on_another_and_both_pages_show_it
    with_db(service("Refunds", ["Authorization"]) + service("Authorization")) do |db|
      refunds = db.instance_by_kind("ApplicationService", "Refunds")
      authorization = db.instance_by_kind("ApplicationService", "Authorization")

      assert_equal ["Authorization"], refunds.relations(:dependsOn, :applicationServices).map(&:name)
      assert_equal ["Authorization"], refunds.relations_grouped.dig("dependsOn", "ApplicationService").map(&:name)
      assert_equal ["Refunds"], authorization.references_grouped.dig("ApplicationService", :dependsOn).map(&:name)
      assert_empty authorization.relations(:dependsOn, :applicationServices)
    end
  end

  def test_a_dependency_on_an_unknown_service_is_reported
    error = assert_raises(Archsight::ResourceError) { lint(service("Refunds", ["Missing"])) }

    assert_includes error.message, "Missing is not defined as kind ApplicationService"
  end

  def test_lint_does_not_report_a_cycle_for_services_depending_on_each_other
    assert_empty lint(service("Refunds", ["Authorization"]) + service("Authorization", ["Refunds"]))
  end

  def test_the_example_declares_two_services_depending_on_each_other
    db = Archsight::Database.new(File.expand_path("../examples/archsight", __dir__), verbose: false, compute_annotations: false)
    db.reload!
    payment = db.instance_by_kind("ApplicationService", "Payment Authorization")
    refunds = db.instance_by_kind("ApplicationService", "Refunds")

    assert_equal ["Refunds"], payment.relations(:dependsOn, :applicationServices).map(&:name)
    assert_equal ["Payment Authorization"], refunds.relations(:dependsOn, :applicationServices).map(&:name)
    assert_empty(Archsight::Linter.new(db).validate)
  end
end
