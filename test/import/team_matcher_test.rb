# frozen_string_literal: true

require "test_helper"
require "archsight/import/team_matcher"

class TeamMatcherTest < Minitest::Test
  def test_analyze_returns_maintainer_and_contributors
    database = MockDatabase.new([
                                  MockTeam.new("Team:Backend", "alice@example.com", "bob@example.com"),
                                  MockTeam.new("Team:Frontend", "carol@example.com")
                                ])

    matcher = Archsight::Import::TeamMatcher.new(database)
    result = matcher.analyze([
                               { "name" => "Alice", "email" => "alice@example.com", "commits" => 50 },
                               { "name" => "Bob", "email" => "bob@example.com", "commits" => 30 },
                               { "name" => "Carol", "email" => "carol@example.com", "commits" => 20 }
                             ])

    assert_equal "Team:Backend", result[:maintainer]
    assert_includes result[:contributors], "Team:Frontend"
  end

  def test_analyze_with_no_contributors_returns_nil
    database = MockDatabase.new([])
    matcher = Archsight::Import::TeamMatcher.new(database)

    result = matcher.analyze([])

    assert_nil result[:maintainer]
    assert_empty result[:contributors]
  end

  def test_analyze_with_nil_contributors_returns_nil
    database = MockDatabase.new([])
    matcher = Archsight::Import::TeamMatcher.new(database)

    result = matcher.analyze(nil)

    assert_nil result[:maintainer]
    assert_empty result[:contributors]
  end

  def test_match_contributor_by_email
    database = MockDatabase.new([
                                  MockTeam.new("Team:Dev", "developer@example.com")
                                ])

    matcher = Archsight::Import::TeamMatcher.new(database)
    team = matcher.match_contributor("Any Name", "developer@example.com")

    assert_equal "Team:Dev", team
  end

  def test_match_contributor_by_email_case_insensitive
    database = MockDatabase.new([
                                  MockTeam.new("Team:Dev", "Developer@Example.COM")
                                ])

    matcher = Archsight::Import::TeamMatcher.new(database)
    team = matcher.match_contributor("Any Name", "developer@example.com")

    assert_equal "Team:Dev", team
  end

  def test_match_contributor_by_name
    database = MockDatabase.new([
                                  MockTeam.new("Team:Dev", nil, nil, "John Developer")
                                ])

    matcher = Archsight::Import::TeamMatcher.new(database)
    team = matcher.match_contributor("John Developer", "unknown@example.com")

    assert_equal "Team:Dev", team
  end

  def test_match_contributor_returns_nil_when_no_match
    database = MockDatabase.new([
                                  MockTeam.new("Team:Dev", "other@example.com")
                                ])

    matcher = Archsight::Import::TeamMatcher.new(database)
    team = matcher.match_contributor("Unknown", "unknown@example.com")

    assert_nil team
  end

  def test_ignores_bot_teams
    database = MockDatabase.new([
                                  MockTeam.new("Bot:Team", "bot@example.com"),
                                  MockTeam.new("Team:Dev", "dev@example.com")
                                ])

    matcher = Archsight::Import::TeamMatcher.new(database)
    result = matcher.analyze([
                               { "name" => "Bot", "email" => "bot@example.com", "commits" => 100 },
                               { "name" => "Dev", "email" => "dev@example.com", "commits" => 10 }
                             ])

    # Bot team should be ignored, so Dev should be maintainer
    assert_equal "Team:Dev", result[:maintainer]
    refute_includes result[:contributors], "Bot:Team"
  end

  def test_parses_name_email_format
    database = MockDatabase.new([
                                  MockTeam.new("Team:Dev", nil, nil, nil, "Alice Developer <alice@example.com>")
                                ])

    matcher = Archsight::Import::TeamMatcher.new(database)
    team = matcher.match_contributor("Any Name", "alice@example.com")

    assert_equal "Team:Dev", team
  end

  def test_handles_database_without_business_actors
    database = MockDatabaseEmpty.new
    matcher = Archsight::Import::TeamMatcher.new(database)

    result = matcher.analyze([
                               { "name" => "Alice", "email" => "alice@example.com", "commits" => 50 }
                             ])

    assert_nil result[:maintainer]
    assert_empty result[:contributors]
  end

  def test_handles_nil_database
    matcher = Archsight::Import::TeamMatcher.new(nil)

    result = matcher.analyze([
                               { "name" => "Alice", "email" => "alice@example.com", "commits" => 50 }
                             ])

    assert_nil result[:maintainer]
    assert_empty result[:contributors]
  end

  class MockTeam
    attr_reader :name, :annotations

    def initialize(name, *emails, lead: nil, members: nil)
      @name = name
      @annotations = {}

      if members
        @annotations["team/members"] = members
      elsif emails.compact.any?
        @annotations["team/members"] = emails.compact.join(",")
      end

      @annotations["team/lead"] = lead if lead
    end
  end

  class MockDatabase
    def initialize(teams)
      @teams = teams
    end

    def instances_by_kind(kind)
      return nil unless kind == "BusinessActor"

      @teams.to_h { |t| [t.name, t] }
    end
  end

  class MockDatabaseEmpty
    def instances_by_kind(_kind)
      {}
    end
  end
end
