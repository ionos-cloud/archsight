# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "rack/test"
require "archsight/editor"
require "archsight/web/application"
require "json"

# `mentions` (links in text) and `depicts` (nodes of diagrams) are derived from what resources and pages say. They are
# not written in files, but behave like any other relation afterwards.
class ReferencesTest < Minitest::Test
  FILES = {
    "model.yaml" => <<~YAML,
      apiVersion: architecture/v1alpha1
      kind: ApplicationComponent
      metadata:
        name: API
        annotations:
          architecture/description: The API stores its data in [[Orders]] and is run by [[ApplicationComponent/Worker]].
          architecture/diagram: |
            component "w" { label "Worker" resource "Worker" }
            component "s" { label "Self" resource "API" }
      spec: {}
      ---
      apiVersion: architecture/v1alpha1
      kind: ApplicationComponent
      metadata:
        name: Worker
      spec: {}
      ---
      apiVersion: architecture/v1alpha1
      kind: ApplicationComponent
      metadata:
        name: Shared
      spec: {}
      ---
      apiVersion: architecture/v1alpha1
      kind: DataObject
      metadata:
        name: Orders
      spec: {}
      ---
      apiVersion: architecture/v1alpha1
      kind: DataObject
      metadata:
        name: Shared
      spec: {}
      ---
      apiVersion: architecture/v1alpha1
      kind: View
      metadata:
        name: Backlog
        annotations:
          view/query: "ApplicationComponent:"
      spec: {}
    YAML
    "docs/overview.md" => <<~MD,
      ---
      title: System Overview
      ---
      Read about [[API]], the [[ApplicationComponent/Worker|worker]] and the [[Details Page]].

      Partial names do not count: [[AP]]. Missing and ambiguous targets do not either: [[Nothing Here]], [[Shared]].

      Code shows links as written: `[[Orders]]`

      ```text
      [[Orders]]
      ```

      ![[View/Backlog]]

      ```asd
      component "o" { label "Orders" resource "Orders" }
      ```

      ![flow](flow.asd)
    MD
    "docs/flow.asd" => %(component "api" { label "API" resource "ApplicationComponent/API" }\n),
    "docs/details.md" => <<~MD,
      ---
      title: Details Page
      ---
      Back to the [[System Overview]] (by title) and to [[overview]] (by name), and to itself: [[details]].

      ```asd
      this is not a valid diagram
      ```
    MD
    "docs/menu.yaml" => <<~YAML
      apiVersion: architecture/v1alpha1
      kind: PageMenu
      metadata:
        name: Docs
      spec:
        contains:
          pages: [overview, details]
    YAML
  }.freeze

  def with_db(files = FILES)
    Dir.mktmpdir do |dir|
      files.each do |path, content|
        FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
        File.write(File.join(dir, path), content)
      end
      db = Archsight::Database.new(dir, verbose: false)
      db.reload!
      yield db
    end
  end

  def instance(db, kind, name) = db.instance_by_kind(kind, name)

  def targets(inst, verb)
    Archsight::Resources::Base.relations.select { |v, _, _| v == verb }.flat_map { |_, key, _| inst.relations(verb, key) }.map(&:name).sort
  end

  def test_text_links_become_mentions
    with_db do |db|
      overview = instance(db, "Page", "overview")

      # the page "Details Page" is named `details`; the embedded view is `Backlog`
      assert_equal %w[API Backlog Worker details], targets(overview, :mentions)
    end
  end

  def test_only_exact_names_count
    with_db do |db|
      mentioned = targets(instance(db, "Page", "overview"), :mentions)

      refute_includes mentioned, "Orders" # only in code
      refute_includes mentioned, "Shared" # exists in two kinds: ambiguous
      assert_equal 4, mentioned.length # [[AP]] (part of a name) and [[Nothing Here]] name nothing
    end
  end

  def test_a_page_is_linked_by_name_or_by_title
    with_db do |db|
      assert_equal ["overview"], targets(instance(db, "Page", "details"), :mentions)
    end
  end

  def test_a_resource_never_refers_to_itself
    with_db do |db|
      refute_includes targets(instance(db, "Page", "details"), :mentions), "details"
      refute_includes targets(instance(db, "ApplicationComponent", "API"), :depicts), "API"
    end
  end

  def test_diagram_blocks_and_embedded_asd_files_become_depicts
    with_db do |db|
      assert_equal %w[API Orders], targets(instance(db, "Page", "overview"), :depicts)
    end
  end

  def test_the_description_and_diagram_of_any_resource_count
    with_db do |db|
      api = instance(db, "ApplicationComponent", "API")

      assert_equal %w[Orders Worker], targets(api, :mentions)
      assert_equal ["Worker"], targets(api, :depicts)
    end
  end

  def test_an_invalid_diagram_names_nothing_and_does_not_stop_the_load
    with_db do |db|
      assert_empty targets(instance(db, "Page", "details"), :depicts)
    end
  end

  def test_both_sides_know_the_relation
    with_db do |db|
      api = instance(db, "ApplicationComponent", "API")
      grouped = api.references_grouped

      assert_equal %w[overview], grouped.dig("Page", :mentions).map(&:name)
      assert_equal %w[overview], grouped.dig("Page", :depicts).map(&:name)
    end
  end

  def test_a_reload_builds_the_relations_again_without_duplicates
    with_db do |db|
      before = targets(instance(db, "Page", "overview"), :mentions)
      db.reload!
      db.reload!

      assert_equal before, targets(instance(db, "Page", "overview"), :mentions)
      assert_equal %w[overview], instance(db, "ApplicationComponent", "API").references_grouped.dig("Page", :mentions).map(&:name)
    end
  end

  def test_derived_verbs_cannot_be_written_in_a_file
    yaml = FILES["model.yaml"].sub("name: Worker\nspec: {}", "name: Worker\nspec:\n  mentions:\n    applicationComponents: [API]")

    refute_equal FILES["model.yaml"], yaml
    error = assert_raises(Archsight::ResourceError) { with_db(FILES.merge("model.yaml" => yaml)) { nil } }
    assert_match(/unknown verb mentions/, error.message)
  end

  def test_queries_follow_derived_relations
    with_db do |db|
      assert_equal %w[overview], db.query("Page: -> ApplicationComponent").map(&:name)
      assert_equal %w[API Worker], db.query("ApplicationComponent: <- Page").map(&:name).sort
      assert_equal %w[Worker], db.query("ApplicationComponent: <{depicts}- ApplicationComponent").map(&:name)
      assert_equal %w[API Worker], db.query("ApplicationComponent: <{mentions}- Page").map(&:name).sort
      assert_empty db.query("ApplicationComponent: <{!mentions,depicts}- Page")
    end
  end

  def test_a_resource_that_only_a_page_mentions_is_no_orphan
    with_db do |db|
      orphans = db.query("ApplicationComponent: <- none").map(&:name)

      assert_equal %w[Shared], orphans
    end
  end

  # Computed annotations sum up costs, teams and repositories of the modelled architecture: a link in a text must not change them
  def test_computed_annotations_do_not_follow_derived_relations
    yaml = FILES["model.yaml"].sub("name: Worker\nspec: {}", "name: Worker\nspec:\n  dependsOn:\n    applicationComponents: [Shared]")
    with_db(FILES.merge("model.yaml" => yaml)) do |db|
      api = instance(db, "ApplicationComponent", "API")
      resolver = Archsight::Annotations::ComputedRelationResolver.new(api, db)

      assert_equal %w[Orders Worker], targets(api, :mentions) # API refers to both, by text
      assert_empty resolver.outgoing # but nothing is modelled for API
      assert_empty resolver.outgoing_transitive
      worker = Archsight::Annotations::ComputedRelationResolver.new(instance(db, "ApplicationComponent", "Worker"), db)

      assert_equal ["Shared"], worker.outgoing.map(&:name) # a written relation is followed
      assert_empty worker.incoming # Worker is mentioned and depicted, not depended upon
      assert_empty Archsight::Annotations::ComputedRelationResolver.new(instance(db, "Page", "overview"), db).outgoing_transitive
    end
  end

  def test_what_users_write_or_choose_lists_only_declared_relations
    derived = Archsight::Resources::DERIVED_VERBS.map(&:to_s)

    refute(Archsight::Editor.available_relations("ApplicationComponent").any? { |verb, _, _| derived.include?(verb.to_s) })
    assert_nil Archsight::Editor.target_class_for_relation("ApplicationComponent", "mentions", "applicationComponents")
    refute_includes Archsight::Template.generate("Page"), "mentions"
    docs = Archsight::Documentation.generate("ApplicationComponent")

    refute_match(/^\| mentions /, docs)
    assert_includes docs, "derived relations `mentions` and `depicts`"
  end

  def test_every_class_has_the_derived_relations_next_to_its_declared_ones
    Archsight::Resources.resource_classes.each_value do |klass|
      extra = klass.relations - klass.declared_relations

      assert_equal Archsight::Resources::DERIVED_VERBS, extra.map(&:first), klass.name
      assert_empty(klass.declared_relations.select { |verb, _, _| Archsight::Resources::DERIVED_VERBS.include?(verb) }, klass.name)
    end
  end
end

class ReferencesAPITest < Minitest::Test
  include Rack::Test::Methods

  def app
    Archsight::Web::Application
  end

  def setup
    Archsight.resources_dir = File.expand_path("../examples/archsight", __dir__)
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
  end

  def json_response
    JSON.parse(last_response.body)
  end

  def test_a_resource_page_lists_the_pages_that_mention_and_depict_it
    get "/api/v1/kinds/ApplicationComponent/instances/Archsight:Core:Database"

    assert_predicate last_response, :ok?
    pages = json_response["references"]["Page"]

    assert_includes pages["depicts"], "diagrams-in-pages"
    assert_includes pages["mentions"], "archsight-architecture"
  end

  def test_a_page_lists_what_it_refers_to
    get "/api/v1/kinds/Page/instances/archsight-architecture"

    relations = json_response["relations"]

    assert_includes relations["mentions"]["ApplicationComponent"], "Archsight:Core:Database"
    assert_includes relations["depicts"]["ApplicationComponent"], "Archsight:Web:API"
  end

  def test_the_linked_from_list_of_a_page_comes_from_the_mentions
    get "/api/v1/pages/searching-and-queries"

    assert_predicate last_response, :ok?
    names = json_response["backlinks"].map { |b| b["name"] }

    assert_includes names, "home"
    assert_equal names.sort, names
  end
end
