# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TextIndexWeightsTest < Minitest::Test
  Weights = Archsight::TextIndex::Weights

  def resource(kind, name, annotations)
    lines = annotations.map { |key, value| "    #{key}: #{value.to_s.inspect}" }.join("\n")
    "---\napiVersion: architecture/v1alpha1\nkind: #{kind}\nmetadata:\n  name: #{name}\n  annotations:\n#{lines}\n"
  end

  def with_db(*resources)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "model.yaml"), resources.join)
      db = Archsight::Database.new(dir, verify: false)
      db.reload!
      yield db
    end
  end

  def search_config(weights)
    resource("Config", "default", { "config/type" => "search" }.merge(weights))
  end

  def text = { "architecture/description" => "Failover to the standby region." }

  def test_defaults_rank_pages_then_application_then_technology
    with_db(resource("TechnologyArtifact", "T", text), resource("ApplicationInterface", "I", text),
            resource("ApplicationService", "S", text), resource("BusinessActor", "B", text)) do |db|
      assert_equal %w[S I B T], Archsight::Query.parse('text: "failover"').ranked(db).map(&:name)

      weights = db.search_weights

      assert_operator weights[Archsight::Resources["Page"]], :>, weights[Archsight::Resources["ApplicationService"]]
      assert_operator weights[Archsight::Resources["Config"]], :<, weights[Archsight::Resources["TechnologyArtifact"]]
    end
  end

  def test_config_sets_a_layer_and_the_kind_wins
    config = search_config("search/weight-technology" => "5", "search/weight-TechnologyArtifact" => "0.1")

    with_db(config, resource("TechnologyArtifact", "T", text), resource("TechnologyService", "TS", text),
            resource("ApplicationService", "S", text)) do |db|
      assert_equal %w[TS S T], Archsight::Query.parse('text: "failover"').ranked(db).map(&:name)
    end
  end

  def test_invalid_values_fall_back_to_the_default
    with_db(search_config("search/weight-technology" => "lots")) do |db|
      assert_in_delta 1.0, db.search_weights[Archsight::Resources["TechnologyArtifact"]]
    end
    assert_match(/expected a number from 0 to 100/, Weights.value_error("lots"))
    assert_match(/expected a number/, Weights.value_error("101"))
    assert_nil Weights.value_error("0.5")
  end
end
