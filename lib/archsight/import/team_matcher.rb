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

  # Team annotation keys that contain member/lead information
  TEAM_ANNOTATION_KEYS = %w[team/members team/lead].freeze

  def initialize(database, corporate_affixes: [])
    @database = database
    @corporate_affixes = corporate_affixes
    @teams = load_teams
    @email_to_team = build_email_index
    @name_to_team = build_name_index
    @member_identities = build_member_identities
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

    # Try corporate username pattern match (e.g. jsmith-ionos -> John Smith)
    if name
      team = pattern_match_username(name)
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

  # Yields (team_name, annotation_value) for each team/members and team/lead annotation
  def each_team_annotation
    @teams.each do |team|
      team_name = team.name
      TEAM_ANNOTATION_KEYS.each do |key|
        value = team.annotations[key]
        yield team_name, value if value && !value.empty?
      end
    end
  end

  def build_email_index
    index = {}

    each_team_annotation do |team_name, value|
      parse_email_list(value).each do |email|
        index[email.downcase] = team_name
      end
    end

    index
  end

  def build_name_index
    index = {}

    each_team_annotation do |team_name, value|
      parse_name_list(value).each do |name|
        normalized = normalize_name(name)
        index[normalized] = team_name if normalized && !normalized.empty?
      end
    end

    index
  end

  # Parse email addresses from team annotation
  # Supports formats: "Name <email>", "email", or comma/newline separated lists
  def parse_email_list(value)
    parse_name_email_pairs(value).filter_map { |pair| pair[:email] }
  end

  # Parse names from team annotation
  # Supports formats: "Name <email>", "First Last", or comma/newline separated lists
  def parse_name_list(value)
    parse_name_email_pairs(value).filter_map { |pair| pair[:name] }
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

  # Match git author name as corporate username pattern {first_initial}{lastname}[-affix] or [affix-]{first_initial}{lastname}
  # e.g. "jsmith-ionos" or "ionos-jsmith" -> initial "j", lastname "smith" -> matches "John Smith"
  #
  # Limitations: Multi-part names (e.g. "Hans von Braun") only match by the last
  # name part ("braun"), so "hvonbraun" would not match. Hyphenated lastnames
  # (e.g. "Meyer-Schmidt") only match the full hyphenated form or the email lastname.
  def pattern_match_username(name)
    username = name.downcase.strip
    return nil unless username.match?(/\A[a-z0-9][-a-z0-9]*\z/)
    return nil if @corporate_affixes.empty?

    @corporate_affixes.each do |affix|
      clean = affix.delete_prefix("-").delete_suffix("-")
      username = username.delete_suffix("-#{clean}")
      username = username.delete_prefix("#{clean}-")
    end
    return nil if username.length < 3

    initial = username[0]
    lastname = username[1..]
    return nil if lastname.length < 3

    candidates = @member_identities.select do |member|
      lastname_match = member[:lastname] == lastname || member[:email_lastname] == lastname
      initial_match = member[:firstname]&.start_with?(initial)
      lastname_match && initial_match
    end

    teams = candidates.map { |c| c[:team] }.uniq
    return teams.first if teams.size == 1

    nil
  end

  # Build identity records for corporate username pattern matching
  def build_member_identities
    identities = []

    each_team_annotation do |team_name, value|
      parse_name_email_pairs(value).each do |entry|
        name_parts = entry[:name]&.downcase&.split(/\s+/)
        next if name_parts.nil? || name_parts.size < 2

        firstname = name_parts.first
        lastname = name_parts.last

        email_prefix = entry[:email]&.split("@")&.first
        email_parts = email_prefix&.split(/[.-]/)
        email_lastname = email_parts&.last&.downcase

        identities << { team: team_name, firstname: firstname, lastname: lastname, email_lastname: email_lastname }
      end
    end

    identities
  end

  # Parse name and email pairs from team annotation
  # Returns array of { name:, email: } hashes from "Name <email>" format
  def parse_name_email_pairs(value)
    return [] if value.nil? || value.empty?

    pairs = []

    value.split(/[,\n]/).each do |entry|
      entry = entry.strip
      next if entry.empty?

      name = nil
      email = nil

      if (match = entry.match(/^([^<]+)<([^>]+)>/))
        name = match[1].strip
        email = match[2].strip
      elsif entry.include?("@")
        email = entry.strip
      else
        name = entry.strip
      end

      pairs << { name: name, email: email } if name || email
    end

    pairs
  end
end
