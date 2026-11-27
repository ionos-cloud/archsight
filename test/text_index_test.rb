# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TextIndexTest < Minitest::Test
  Expression = Archsight::TextIndex::Expression

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

  def model
    [
      resource("ApplicationService", "Billing", "architecture/description" => "Handles invoices. Failover to the standby region.",
                                                "link/jira" => "https://tracker.example/PROJ-1234"),
      resource("ApplicationService", "Mailer", "architecture/description" => "Sends mail with retries. Café menu."),
      resource("TechnologyArtifact", "failover-operator", "architecture/description" => "An operator for clusters."),
      resource("TechnologyArtifact", "standby-tool", "architecture/description" => "Active standby replication, and failover.")
    ]
  end

  def names(db, expression)
    db.text_index.search(Expression.translate(expression)).keys.map(&:name).sort
  end

  def test_words_phrases_prefix_and_operators
    with_db(*model) do |db|
      assert_equal %w[Billing failover-operator standby-tool], names(db, "failover")
      assert_equal %w[Billing standby-tool], names(db, "failover standby")
      assert_equal %w[Billing Mailer failover-operator standby-tool], names(db, "failover OR mail")
      assert_equal %w[Billing failover-operator], names(db, "failover NOT replication")
      assert_equal %w[standby-tool], names(db, '"active standby"')
      assert_equal %w[failover-operator], names(db, "cluster*")
      assert_equal %w[Billing], names(db, "PROJ-1234")
    end
  end

  def test_word_forms_case_and_accents
    with_db(*model) do |db|
      assert_equal %w[Billing failover-operator standby-tool], names(db, "FAILOVERS")
      assert_equal %w[Mailer], names(db, "retry")
      assert_equal %w[Mailer], names(db, "cafe")
    end
  end

  def test_words_in_the_name_rank_above_words_in_the_body
    with_db(*model) do |db|
      scores = db.text_index.search(Expression.translate("failover"))

      assert_operator scores.find { |r, _| r.name == "failover-operator" }.last, :>, scores.find { |r, _| r.name == "Billing" }.last
    end
  end

  def test_bad_syntax_is_a_query_error
    with_db(*model) do |db|
      assert_raises(Archsight::Query::QueryError) { db.text_index.search("failover AND") }
      assert_raises(Archsight::Query::QueryError) { Expression.translate("( )") }
    end
  end

  def test_the_index_follows_reload
    with_db(*model) do |db|
      first = db.text_index

      assert_same first, db.text_index
      File.write(File.join(db.path, "more.yaml"), resource("ApplicationService", "Ledger", "architecture/description" => "Failover too."))
      db.reload!

      refute_same first, db.text_index
      assert_includes names(db, "failover"), "Ledger"
    end
  end

  def test_translate_quotes_what_is_no_fts_syntax
    assert_equal '"PROJ-1234" "Archsight:CLI" "C++"', Expression.translate("PROJ-1234 Archsight:CLI C++")
    assert_equal '"active standby" fail* OR x NOT y ( a b )', Expression.translate('"active standby" fail* OR x NOT y (a b)')
    assert_equal "kube* fail* \"a b\"", Expression.translate('kube fail "a b"', prefix: true)
    assert_equal %w[failover standby], Expression.terms("failover NOT region OR standby")
  end

  def test_query_language_uses_the_index_and_ranks
    with_db(*model) do |db|
      assert_equal %w[Billing standby-tool], Archsight::Query.parse('text: "failover standby"').filter(db).map(&:name).sort
      # the word in the name ranks first; with the word in the body the service (weight 2) beats the artifact (1)
      ranked = Archsight::Query.parse('text: "failover"').ranked(db).map(&:name)

      assert_equal %w[failover-operator Billing standby-tool], ranked
      assert_predicate Archsight::Query.parse('text: "failover"'), :ranked?
      refute_predicate Archsight::Query.parse("text =~ /failover/"), :ranked?
      refute_predicate Archsight::Query.parse('!(text: "failover")'), :ranked?
    end
  end

  def test_search_box_words_match_name_or_text
    with_db(*model) do |db|
      query = Archsight::Query.parse("fail stand", bare_words: :search)

      assert_instance_of Archsight::Query::AST::SearchTerms, query.ast.expression
      assert_equal %w[Billing standby-tool], query.filter(db).map(&:name).sort
      # `oper` is only part of a word in the name (failover-operator): the name search finds it
      assert_equal %w[failover-operator], Archsight::Query.parse("perat", bare_words: :search).filter(db).map(&:name)
    end
  end
end
