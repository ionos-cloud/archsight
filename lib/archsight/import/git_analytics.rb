# frozen_string_literal: true

require "time"
require "open3"
require "archsight/import"

# Repository health metrics analyzer (human activity only)
#
# Analyzes git repositories to extract:
# - Commits, contributors, top contributors (full history for team matching)
# - Recent tags (last 2 years)
# - Bus factor risk (low / medium / high / unknown)
# - Activity status (active / bot-only / abandoned)
# - Deployment types, workflow platforms, OCI images
# - Agentic tools configuration
# - README description and documentation links
#
# @example
#   analytics = Archsight::Import::GitAnalytics.new("/path/to/repo")
#   result = analytics.analyze
class Archsight::Import::GitAnalytics
  DEFAULT_SINCE_DAYS = 180
  DEFAULT_HIGH_THRESH = 0.75
  DEFAULT_MED_THRESH = 0.50

  IGNORED_BOTS = [
    /dependabot/i,
    /renovate\[bot\]/i,
    /greenkeeper/i,
    /ci\s+bot/i
  ].freeze

  AGENTIC_FILES = {
    "claude" => %w[claude.md .claude.md docs/claude.md CLAUDE.md],
    "cursor" => %w[.cursorrules .cursor/rules cursor.md],
    "aider" => %w[.aider.conf.yml aider.md docs/aider.md],
    "github-copilot" => %w[.github/copilot-instructions.md],
    "agents" => %w[agents.md .agents.md docs/agents.md]
  }.freeze

  def initialize(repo_path, options = {})
    @repo_path = repo_path
    @since_days = options[:since_days] || DEFAULT_SINCE_DAYS
    @high_thresh = options[:high_thresh] || DEFAULT_HIGH_THRESH
    @med_thresh = options[:med_thresh] || DEFAULT_MED_THRESH
    @since_iso = (Time.now - (@since_days * 86_400)).utc.iso8601
  end

  def analyze
    {
      "commits" => commit_count,
      "commits_per_month" => commits_per_month,
      "contributors" => contributor_count,
      "contributors_6m" => contributors_6m_unique,
      "contributors_per_month" => contributors_per_month,
      "top_contributors" => top_contributors,
      "recent_tags" => recent_tags,
      "activity_status" => activity_status,
      "created_at" => created_at,
      "last_human_commit" => last_human_commit,
      "bus_factor_risk" => bus_factor_risk,
      "agentic_tools" => agentic_tools,
      "deployment_types" => deployment_types,
      "workflow_platforms" => workflow_platforms,
      "workflow_types" => workflow_types,
      "oci_images" => oci_images,
      "description" => description,
      "documentation_links" => documentation_links
    }
  end

  private

  # Run a git command inside the repo
  def git(*git_args)
    cmd = ["git", "-C", @repo_path] + git_args
    out, err, status = Open3.capture3(*cmd)
    raise "git failed: #{cmd.join(" ")}\n#{err}" unless status.success?

    out.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "?").strip
  end

  # Check if author string matches bot patterns
  def bot?(author_str)
    IGNORED_BOTS.any? { |re| author_str =~ re }
  end

  # Determine the most recent ref (local or remote)
  def most_recent_ref
    @most_recent_ref ||= find_most_recent_ref
  end

  def find_most_recent_ref
    refs = git(
      "for-each-ref",
      "--sort=-committerdate",
      "--format=%(refname:short)",
      "refs/heads/",
      "refs/remotes/"
    ).split("\n")

    ref = refs.find { |r| !r.empty? }
    return ref if ref && !ref.empty?

    %w[main master].each do |candidate|
      return candidate if git("rev-parse", "--verify", candidate)
    rescue StandardError
      nil
    end

    "HEAD"
  rescue StandardError
    "HEAD"
  end

  # Get all commits from full history (raw, including bots)
  def raw_commit_lines
    @raw_commit_lines ||= git(
      "log",
      most_recent_ref,
      "--no-merges",
      "--pretty=format:%H|%an|%ae",
      "--"
    ).split("\n").map { |line| line.split("|", 3) }
  end

  # Get recent commits (within since_days window)
  def recent_commit_lines
    @recent_commit_lines ||= git(
      "log",
      most_recent_ref,
      "--since=#{@since_iso}",
      "--no-merges",
      "--pretty=format:%H|%an|%ae",
      "--"
    ).split("\n").map { |line| line.split("|", 3) }
  end

  # Get human-only commits from full history
  def human_commits
    @human_commits ||= raw_commit_lines.reject { |_, author, _| bot?(author) }
  end

  # Get recent human-only commits for activity status
  def recent_human_commits
    @recent_human_commits ||= recent_commit_lines.reject { |_, author, _| bot?(author) }
  end

  # Get commits from the last 6 months (for bus factor calculation)
  def commits_6m
    @commits_6m ||= begin
      six_months_ago = (Time.now - (6 * 30 * 24 * 60 * 60)).strftime("%Y-%m-%d")
      git(
        "log",
        most_recent_ref,
        "--since=#{six_months_ago}",
        "--no-merges",
        "--pretty=format:%H|%an|%ae",
        "--"
      ).split("\n").map { |line| line.split("|", 3) }
    end
  end

  # Get human-only commits from the last 6 months
  def human_commits_6m
    @human_commits_6m ||= commits_6m.reject { |_, author, _| bot?(author) }
  end

  def commit_count
    human_commits.size
  end

  def last_human_commit
    return nil if human_commits.empty?

    most_recent_hash = human_commits.first.first
    git("show", "-s", "--format=%cI", most_recent_hash)
  end

  def created_at
    return nil if raw_commit_lines.empty?

    oldest_hash = raw_commit_lines.last.first
    git("show", "-s", "--format=%cI", oldest_hash)
  rescue StandardError
    nil
  end

  def commits_per_month
    return [] if raw_commit_lines.empty?

    dates_output = git(
      "log",
      most_recent_ref,
      "--no-merges",
      "--pretty=format:%cI",
      "--"
    )
    return [] if dates_output.empty?

    commit_dates = dates_output.split("\n").filter_map do |d|
      Time.parse(d)
    rescue StandardError
      nil
    end
    return [] if commit_dates.empty?

    counts_by_month = commit_dates.each_with_object(Hash.new(0)) do |date, h|
      key = date.strftime("%Y-%m")
      h[key] += 1
    end

    first_month = commit_dates.min.strftime("%Y-%m")
    last_month = Time.now.strftime("%Y-%m")

    all_months = generate_month_range(first_month, last_month)
    all_months.map { |m| counts_by_month[m] || 0 }
  end

  def generate_month_range(start_month, end_month)
    start_year, start_mon = start_month.split("-").map(&:to_i)
    end_year, end_mon = end_month.split("-").map(&:to_i)

    months = []
    year = start_year
    mon = start_mon
    while year < end_year || (year == end_year && mon <= end_mon)
      months << format("%04d-%02d", year, mon)
      mon += 1
      if mon > 12
        mon = 1
        year += 1
      end
    end
    months
  end

  def contributor_count
    contrib_counter.size
  end

  def contributors_per_month
    return [] if human_commits.empty?

    dates_output = git(
      "log",
      most_recent_ref,
      "--no-merges",
      "--pretty=format:%cI|%an|%ae",
      "--"
    )
    return [] if dates_output.empty?

    commits_with_dates = dates_output.split("\n").filter_map do |line|
      parts = line.split("|", 3)
      next nil if parts.length < 3

      date_str, author_name, author_email = parts
      next nil if bot?(author_name)

      date = begin
        Time.parse(date_str)
      rescue StandardError
        nil
      end
      next nil unless date

      { date: date, author: "#{author_name}|#{author_email}" }
    end

    return [] if commits_with_dates.empty?

    contributors_by_month = commits_with_dates.each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |commit, h|
      key = commit[:date].strftime("%Y-%m")
      h[key] << commit[:author]
    end

    first_month = commits_with_dates.map { |c| c[:date] }.min.strftime("%Y-%m")
    last_month = Time.now.strftime("%Y-%m")

    all_months = generate_month_range(first_month, last_month)
    all_months.map { |m| contributors_by_month[m]&.size || 0 }
  end

  def contrib_counter
    @contrib_counter ||= human_commits.each_with_object(Hash.new { |h, k| h[k] = 0 }) do |(_, name, email), h|
      key = [name, email]
      h[key] += 1
    end
  end

  def top_contributors
    contrib_counter
      .sort_by { |_key, cnt| -cnt }
      .first(50)
      .map { |(name, email), cnt| { "name" => name, "email" => email, "commits" => cnt } }
  end

  def recent_tags
    @recent_tags ||= begin
      two_years_ago = (Time.now - (730 * 86_400)).utc.iso8601
      raw_tags = git(
        "for-each-ref",
        "--sort=-creatordate",
        "--format=%(refname:short) %(creatordate:iso8601)",
        "refs/tags"
      )

      raw_tags.each_line
              .map { |l| l.split(" ", 2) }
              .select { |_, date| date && date >= two_years_ago }
              .map { |name, date| { "name" => name, "date" => date.chomp } }
              .first(10)
    end
  end

  def activity_status
    if recent_human_commits.empty? && recent_commit_lines.empty?
      "abandoned"
    elsif recent_human_commits.empty?
      "bot-only"
    else
      "active"
    end
  end

  def contributors_6m_unique
    @contributors_6m_unique ||= calculate_contributors_6m_unique
  end

  def calculate_contributors_6m_unique
    return 0 if human_commits_6m.empty?

    human_commits_6m.map { |_, author, _| author }.uniq.size
  end

  def bus_factor_risk
    return "unknown" if human_commits_6m.empty?

    commits_by_author = Hash.new(0)
    human_commits_6m.each { |_, author, _| commits_by_author[author] += 1 }

    total_6m = commits_by_author.values.sum
    top_6m = commits_by_author.values.max

    share = total_6m.zero? ? 0.0 : top_6m.to_f / total_6m

    if share > @high_thresh
      "high"
    elsif share > @med_thresh
      "medium"
    else
      "low"
    end
  end

  def agentic_tools
    tools = []

    AGENTIC_FILES.each do |tool, files|
      files.each do |file|
        if File.exist?(File.join(@repo_path, file))
          tools << tool
          break
        end
      end
    end

    tools.uniq!
    tools.empty? ? "none" : tools.join(",")
  end

  def deployment_types
    types = []
    types << "container" if File.exist?(File.join(@repo_path, "Dockerfile"))
    types << "chart" if Dir.exist?(File.join(@repo_path, "charts")) || Dir.exist?(File.join(@repo_path, "helm"))
    types << "debian" if File.exist?(File.join(@repo_path, "debian/control"))
    types << "rpm" if File.exist?(File.join(@repo_path, ".spec")) || Dir.glob(File.join(@repo_path, "*.spec")).any?

    makefile_path = File.join(@repo_path, "Makefile")
    if File.exist?(makefile_path)
      makefile_content = File.read(makefile_path)
      types << "binary" if makefile_content.match?(/\bbuild\b/i)
    end

    types << "none" if types.empty?
    types.join(",")
  end

  def oci_images
    @oci_images ||= begin
      images = []

      # Search GitHub Actions workflows
      workflows_dir = File.join(@repo_path, ".github/workflows")
      if Dir.exist?(workflows_dir)
        Dir.glob(File.join(workflows_dir, "*.{yml,yaml}")).each do |workflow_file|
          images.concat(extract_oci_images_from_file(workflow_file))
        end
      end

      # Search GitLab CI
      gitlab_ci = File.join(@repo_path, ".gitlab-ci.yml")
      images.concat(extract_oci_images_from_file(gitlab_ci)) if File.exist?(gitlab_ci)

      # Infer from Dockerfile if no explicit references found
      if deployment_types.include?("container") && images.empty?
        repo_name = File.basename(@repo_path)
        images << "ghcr.io/ionos-cloud/#{repo_name}" if @repo_path.include?("ionos-cloud") || @repo_path.include?("github.com")
      end

      images.uniq
    end
  end

  def extract_oci_images_from_file(file_path)
    return [] unless File.exist?(file_path)

    images = []
    content = File.read(file_path)

    # Pattern 1: images: ghcr.io/ionos-cloud/repo-name or harbor...
    content.scan(/images:\s*[|\n]\s*([^\s]+(?:ghcr\.io|harbor)[^\s]+)/m).flatten.each do |img|
      img.split("\n").each do |line|
        line = line.strip
        next if line.empty? || line.start_with?("type=")

        images << line if line.match?(/ghcr\.io|harbor/)
      end
    end

    # Pattern 2: Direct image references
    content.scan(%r{(?:ghcr\.io|harbor[^\s]*)/([^\s:]+)}).flatten.each do |path|
      images << "ghcr.io/#{path}" unless images.any? { |img| img.include?(path) }
    end

    images
  end

  def workflow_platforms
    platforms = []
    platforms << "github-actions" if Dir.exist?(File.join(@repo_path, ".github/workflows"))
    platforms << "gitlab-ci" if File.exist?(File.join(@repo_path, ".gitlab-ci.yml"))
    platforms << "makefile" if File.exist?(File.join(@repo_path, "Makefile"))
    platforms << "none" if platforms.empty?
    platforms.join(",")
  end

  def workflow_types
    types = []
    workflow_files = collect_workflow_files

    workflow_files.each do |file|
      next unless File.exist?(file)

      content = File.read(file)
      content_lower = content.downcase

      types << "build" if content_lower.match?(/\b(build|compile|docker build|go build|npm run build|maven|gradle)\b/)
      types << "test" if content_lower.match?(/\btest[^-]|\bmake test\b/)
      types << "unit-test" if content_lower.match?(/\b(unit[- ]test|unittest|test.*unit|jest|pytest|rspec|go test.*-short)\b/)
      types << "integration-test" if content_lower.match?(/\b(integration[- ]test|test.*integration|e2e|end-to-end)\b/)
      types << "smoke-test" if content_lower.match?(/\b(smoke[- ]test|test.*smoke)\b/)
      types << "deploy" if content_lower.match?(/\b(deploy|push|publish|release|kubectl apply|helm (install|upgrade))\b/)
      types << "lint" if content_lower.match?(/\b(lint|eslint|rubocop|pylint|golangci-lint|flake8|checkstyle)\b/)
      types << "security-scan" if content_lower.match?(/\b(trivy|snyk|sonarqube|codeql|security[- ]scan|vulnerability|scan.*image|bundler-audit|brakeman|ruby_audit|npm audit|yarn audit|safety check|bandit|gosec)\b/)
      types << "dependency-update" if content_lower.match?(/\b(dependabot|renovate|dependency.*update|update.*depend)\b/)
      types << "ticket-creation" if content_lower.match?(/\b(jira|tosm|create.*ticket|create.*issue|atlassian)\b/)
    end

    # Check for dependency update config files
    if File.exist?(File.join(@repo_path, ".github/dependabot.yml")) ||
       File.exist?(File.join(@repo_path, ".github/dependabot.yaml")) ||
       File.exist?(File.join(@repo_path, "renovate.json")) ||
       File.exist?(File.join(@repo_path, ".renovaterc"))
      types << "dependency-update"
    end

    types.uniq!
    types << "none" if types.empty?
    types.join(",")
  end

  def collect_workflow_files
    files = []
    files += Dir.glob(File.join(@repo_path, ".github/workflows/*.{yml,yaml}"))
    files << File.join(@repo_path, ".gitlab-ci.yml") if File.exist?(File.join(@repo_path, ".gitlab-ci.yml"))
    files << File.join(@repo_path, "Makefile") if File.exist?(File.join(@repo_path, "Makefile"))
    files
  end

  def description
    @description ||= extract_description
  end

  def documentation_links
    @documentation_links ||= extract_links
  end

  def extract_links
    readme_files = Dir.glob(File.join(@repo_path, "README*"), File::FNM_CASEFOLD)
    readme_file = readme_files.first
    return [] unless readme_file && File.exist?(readme_file)

    content = read_file_with_encoding(readme_file)
    return [] unless content

    links = []

    # Match markdown links: [text](url) - only http/https
    content.scan(/\[([^\]]+)\]\(([^)]+)\)/).each do |text, url|
      next unless url.match?(%r{^https?://})
      next if text.match?(/^!/) # Skip images

      url = url.strip.split(/\s+/).first
      clean_text = text.strip.gsub(/[*_`~]/, "")
      links << { "text" => clean_text, "url" => url }
    end

    # Match bare URLs (http/https)
    content.scan(%r{(?<![(\[])(https?://[^\s<>)\]]+)}).flatten.each do |url|
      next if links.any? { |link| link["url"] == url }

      domain = begin
        url.match(%r{https?://([^/]+)})[1]
      rescue StandardError
        url
      end
      links << { "text" => domain, "url" => url }
    end

    links.uniq { |link| link["url"] }
  end

  def extract_description
    readme_files = Dir.glob(File.join(@repo_path, "README*"), File::FNM_CASEFOLD)
    readme_file = readme_files.first
    return nil unless readme_file && File.exist?(readme_file)

    content = read_file_with_encoding(readme_file)
    return nil unless content

    description_lines = extract_description_lines(content)
    return nil if description_lines.empty?

    desc = description_lines.join("\n").strip
    truncate_at_sentence_boundary(desc)
  end

  def read_file_with_encoding(file_path)
    raw = File.read(file_path, mode: "rb")

    if raw.start_with?("\xFF\xFE".b)
      raw.force_encoding("UTF-16LE").encode("UTF-8")
    elsif raw.start_with?("\xFE\xFF".b)
      raw.force_encoding("UTF-16BE").encode("UTF-8")
    elsif raw.start_with?("\xEF\xBB\xBF".b)
      raw.force_encoding("UTF-8")[3..]
    else
      raw.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    end
  rescue StandardError
    nil
  end

  def extract_description_lines(content)
    content = content.sub(/^\uFEFF/, "")

    lines = content.lines
    description_lines = []
    found_first_paragraph = false
    blank_line_count = 0

    lines.each do |line|
      line = line.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
      stripped = line.strip

      unless found_first_paragraph
        next if stripped.empty?
        next if stripped.match?(/^#\s+/)
        next if stripped.match?(/^\[!\[|^!\[/)
        next if stripped.match?(/^\[.*\]\(.*\)$/) && !stripped.include?(" ")

        found_first_paragraph = true
      end

      if stripped.empty?
        blank_line_count += 1
        break if blank_line_count >= 2 && description_lines.any?

        description_lines << "" if description_lines.any?
        next
      else
        blank_line_count = 0
      end

      break if stripped.match?(/^##\s+/)

      description_lines << stripped
      break if description_lines.join("\n").length > 1500
    end

    description_lines
  end

  def truncate_at_sentence_boundary(description)
    return description if description.length <= 600

    paragraphs = description.split(/\n\n+/)
    result_paragraphs = []
    current_length = 0

    paragraphs.each do |para|
      candidate_length = current_length + (result_paragraphs.empty? ? 0 : 2) + para.length
      break if current_length >= 600 && candidate_length > 1200

      result_paragraphs << para
      current_length = candidate_length
      break if current_length > 1200
    end

    return description if result_paragraphs.empty?

    result_paragraphs.join("\n\n")
  end
end
