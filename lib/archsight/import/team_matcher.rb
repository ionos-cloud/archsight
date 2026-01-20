# frozen_string_literal: true

require "archsight/import"

# Matches git contributors to BusinessActor teams
#
# Uses team member email and name patterns from BusinessActor annotations
# to match top contributors from git history to teams.
#
# @example
#   matcher = Archsight::Import::TeamMatcher.new(database)
#   result = matcher.analyze(top_contributors)
#   # => { maintainer: "Team:Engineering", contributors: ["Team:QA", "Team:Ops"] }
class Archsight::Import::TeamMatcher
  # Teams to ignore when matching (bots, unknown, etc.)
  IGNORED_TEAMS = %w[Bot:Team No:Team Team:Unknown Team:Bot].freeze

  def initialize(database)
    @database = database
    @teams = load_teams
    @email_to_team = build_email_index
    @name_to_team = build_name_index
  end

  # Analyze top contributors and return team assignments
  #
  # @param top_contributors [Array<Hash>] List of contributors with "name", "email", "commits" keys
  # @return [Hash] { maintainer: String?, contributors: [String] }
  def analyze(top_contributors)
    return { maintainer: nil, contributors: [] } if top_contributors.nil? || top_contributors.empty?

    team_commits = Hash.new(0)

    top_contributors.each do |contributor|
      team = match_contributor(contributor["name"], contributor["email"])
      next unless team
      next if IGNORED_TEAMS.include?(team)

      team_commits[team] += contributor["commits"]
    end

    return { maintainer: nil, contributors: [] } if team_commits.empty?

    # Sort by commits descending
    sorted = team_commits.sort_by { |_, commits| -commits }

    {
      maintainer: sorted.first&.first,
      contributors: sorted.drop(1).map(&:first)
    }
  end

  # Match a single contributor to a team
  #
  # @param name [String] Contributor name
  # @param email [String] Contributor email
  # @return [String, nil] Team name or nil if no match
  def match_contributor(name, email)
    return nil if name.nil? && email.nil?

    # Try exact email match first (most reliable)
    if email
      normalized_email = email.to_s.downcase.strip
      team = @email_to_team[normalized_email]
      return team if team
    end

    # Try name match (less reliable, but useful for LDAP-style names)
    if name
      normalized_name = normalize_name(name)
      team = @name_to_team[normalized_name]
      return team if team
    end

    nil
  end

  private

  def load_teams
    return {} unless @database

    begin
      @database.instances_by_kind("BusinessActor")&.values || []
    rescue StandardError
      []
    end
  end

  def build_email_index
    index = {}

    @teams.each do |team|
      team_name = team.name

      # Extract emails from team/members annotation
      members = team.annotations["team/members"]
      parse_email_list(members).each do |email|
        index[email.downcase] = team_name
      end

      # Extract email from team/lead annotation
      lead = team.annotations["team/lead"]
      parse_email_list(lead).each do |email|
        index[email.downcase] = team_name
      end
    end

    index
  end

  def build_name_index
    index = {}

    @teams.each do |team|
      team_name = team.name

      # Extract names from team/members annotation
      members = team.annotations["team/members"]
      parse_name_list(members).each do |name|
        normalized = normalize_name(name)
        index[normalized] = team_name if normalized && !normalized.empty?
      end

      # Extract name from team/lead annotation
      lead = team.annotations["team/lead"]
      parse_name_list(lead).each do |name|
        normalized = normalize_name(name)
        index[normalized] = team_name if normalized && !normalized.empty?
      end
    end

    index
  end

  # Parse email addresses from team annotation
  # Supports formats: "Name <email>", "email", or comma/newline separated lists
  def parse_email_list(value)
    return [] if value.nil? || value.empty?

    emails = []

    # Split by comma or newline
    value.split(/[,\n]/).each do |entry|
      entry = entry.strip
      next if entry.empty?

      # Try to extract email from "Name <email>" format
      if (match = entry.match(/<([^>]+)>/))
        emails << match[1].strip
      elsif entry.include?("@")
        # Plain email address
        emails << entry
      end
    end

    emails
  end

  # Parse names from team annotation
  # Supports formats: "Name <email>", "First Last", or comma/newline separated lists
  def parse_name_list(value)
    return [] if value.nil? || value.empty?

    names = []

    # Split by comma or newline
    value.split(/[,\n]/).each do |entry|
      entry = entry.strip
      next if entry.empty?

      # Try to extract name from "Name <email>" format
      if (match = entry.match(/^([^<]+)</))
        name = match[1].strip
        names << name unless name.empty?
      elsif !entry.include?("@")
        # Plain name (no email)
        names << entry
      end
    end

    names
  end

  # Normalize name for matching
  # Converts to lowercase, removes extra spaces, handles common variations
  def normalize_name(name)
    return nil if name.nil?

    name.to_s
        .downcase
        .gsub(/\s+/, " ")
        .strip
  end
end
