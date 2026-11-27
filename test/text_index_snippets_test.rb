# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class TextIndexSnippetsTest < Minitest::Test
  Snippets = Archsight::TextIndex::Snippets
  Matcher = Archsight::TextIndex::Matcher

  LONG = "#{"Handles invoices for all customers of the shop and keeps them for ten years. " * 4}" \
         "Failover goes to the standby region when the primary fails. #{"Reports are sent monthly to finance. " * 4}".freeze

  def resource(kind, name, annotations)
    lines = annotations.map { |key, value| "    #{key}: #{value.to_s.inspect}" }.join("\n")
    "---\napiVersion: architecture/v1alpha1\nkind: #{kind}\nmetadata:\n  name: #{name}\n  annotations:\n#{lines}\n"
  end

  def with_db
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "model.yaml"), [
        resource("ApplicationService", "Billing", "architecture/description" => LONG, "architecture/tags" => "billing,failover",
                                                  "link/jira" => "https://tracker.example/PROJ-1234"),
        resource("ApplicationService", "Café", "architecture/title" => "Café Deployment", "architecture/description" => "Deployed nightly.")
      ].join)
      File.write(File.join(dir, "page.md"), "---\ntitle: Runbook\n---\n# Runbook\n\nIf the **primary** fails, see [the failover guide](x.md) and [[Billing]].\n")
      db = Archsight::Database.new(dir, verify: false)
      db.reload!
      yield db
    end
  end

  def snippets(db, query, name, **)
    parsed = Archsight::Query.parse(query, bare_words: :search)
    instance = parsed.filter(db).find { |r| r.name == name }
    Snippets.for(instance, Matcher.for(parsed, db), **)
  end

  def marked(snippet)
    snippet[:marks].map { |from, to| snippet[:text][from...to] }
  end

  def test_the_excerpt_is_the_window_with_the_searched_words
    with_db do |db|
      best = snippets(db, 'text: "failovers standby"', "Billing").first

      assert_equal "architecture/description", best[:key]
      assert_equal "Description", best[:title]
      assert best[:text].start_with?("…") && best[:text].end_with?("…")
      assert_operator best[:text].length, :<=, 182
      assert_equal %w[Failover standby], marked(best) # word forms by stem, as written in the text
    end
  end

  def test_the_annotation_with_most_different_words_comes_first
    with_db do |db|
      found = snippets(db, "failover primary", "Billing")

      assert_equal "architecture/description", found.first[:key]
      assert_equal "architecture/tags", found.last[:key]
      assert_equal 2, found.size
    end
  end

  def test_prefix_words_match_as_written_and_accents_are_ignored
    with_db do |db|
      assert_equal ["Deployed"], marked(snippets(db, "deploy", "Café").first)
      parsed = Archsight::Query.parse("cafe", bare_words: :search)
      cafe = db.instance_by_kind("ApplicationService", "Café")

      assert_equal({ title: "Café Deployment", title_marks: [[0, 4]] }, Snippets.title(cafe, Matcher.for(parsed, db)))
    end
  end

  def test_markdown_is_plain_text_and_the_title_heading_is_left_out
    with_db do |db|
      found = snippets(db, 'Page: text: "failover"', "page").first

      assert_equal "If the primary fails, see the failover guide and Billing.", found[:text]
      assert_equal ["failover"], marked(found)
    end
  end

  def test_regex_conditions_use_their_keys_and_the_markdown_source
    with_db do |db|
      assert_equal(["link/jira"], snippets(db, 'text(link/*) =~ "proj-\\\\d+"', "Billing").map { |s| s[:key] })
      assert_equal ["[[Bill"], marked(snippets(db, "text =~ /\\[\\[Bill/", "page").first)
    end
  end

  def test_no_text_condition_no_excerpts
    with_db do |db|
      assert_empty snippets(db, 'name == "Billing"', "Billing")
      assert_predicate Matcher.for(Archsight::Query.parse('name == "Billing"'), db), :empty?
    end
  end
end
