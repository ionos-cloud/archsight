# frozen_string_literal: true

module Archsight
  # Helpers provides utility functions for the architecture tool
  module Helpers
    module_function

    # Make path relative to resources directory
    def relative_error_path(path)
      # Find 'resources/' in path and return from there
      if (idx = path.index("resources/"))
        path[idx..]
      else
        File.basename(path)
      end
    end

    # Extract context lines around a YAML document containing an error
    # Returns array of hashes with :line_no, :content, :selected keys
    def error_context_lines(path, error_line_no, context_lines: 5)
      return [] unless File.exist?(path)

      lines = File.readlines(path, chomp: true)
      error_idx = error_line_no - 1 # Convert to 0-indexed

      # Find the start of the YAML document (--- separator at or before error line)
      doc_start = error_idx
      doc_start -= 1 while doc_start.positive? && lines[doc_start] != "---"

      # Find the end of the YAML document (next --- or end of file)
      doc_end = error_idx + 1
      doc_end += 1 while doc_end < lines.length && lines[doc_end] != "---"
      doc_end -= 1 # Don't include the next ---

      # Show context_lines before doc start, full document, and context_lines after doc end
      context_start = [doc_start - context_lines, 0].max
      context_end = [doc_end + context_lines, lines.length - 1].min

      (context_start..context_end).map do |i|
        {
          line_no: i + 1,
          content: lines[i],
          selected: (i + 1) == error_line_no
        }
      end
    end

    def classify(val)
      val.to_s.split("-").map(&:capitalize).join
    end

    def deep_merge(hash1, hash2)
      hash1.dup.merge(hash2) do |_, old_value, new_value|
        if old_value.is_a?(Hash) && new_value.is_a?(Hash)
          deep_merge(old_value, new_value)
        elsif old_value.is_a?(Array) && new_value.is_a?(Array)
          (old_value + new_value).uniq
        else
          new_value
        end
      end
    end

    # Generate htmx attributes for a custom search query
    def search_link_attrs(query)
      search_url = "/search?#{URI.encode_www_form(q: query)}"
      {
        "href" => search_url,
        "hx-post" => "/search",
        "hx-vals" => { q: query }.to_json,
        "hx-swap" => "innerHTML",
        "hx-target" => ".content",
        "hx-push-url" => search_url
      }
    end

    # Generate htmx attributes for filtering by annotation (convenience wrapper)
    def filter_link_attrs(tag, value, method = "==", kind = nil)
      query = "#{tag} #{method} \"#{value}\""
      query = "#{kind}: #{query}" if kind
      search_link_attrs(query)
    end

    # Get icon class for a URL based on domain patterns
    def icon_for_url(url)
      case url
      when %r{docs\.google\.com/(document|spreadsheets|presentation)}
        "iconoir-google-docs"
      when /github\.com/
        "iconoir-github"
      when /gitlab/
        "iconoir-git-fork"
      when /confluence\.|atlassian\.net/
        "iconoir-page-edit"
      when /jira\.|atlassian\.net.*jira/
        "iconoir-list"
      when /grafana/
        "iconoir-graph-up"
      when /prometheus/
        "iconoir-database"
      when /api\./
        "iconoir-code"
      when /docs\./
        "iconoir-book"
      else
        "iconoir-internet"
      end
    end

    # Convert a GitHub git URL to a raw.githubusercontent.com base URL
    # @param git_url [String] Git URL like "git@github.com:owner/repo.git" or "https://github.com/owner/repo"
    # @param branch [String] Branch name, defaults to "main"
    # @return [String, nil] Base URL for raw content, or nil if not a GitHub URL
    def github_raw_base_url(git_url, branch: "main")
      return nil unless git_url

      # Extract owner/repo from various GitHub URL formats
      match = git_url.match(%r{github\.com[:/]([^/]+)/([^/.]+)})
      return nil unless match

      owner = match[1]
      repo = match[2]
      "https://raw.githubusercontent.com/#{owner}/#{repo}/#{branch}"
    end

    # Resolve relative paths in HTML/Markdown content to absolute URLs
    # @param content [String] HTML content with potential relative paths
    # @param base_url [String] Base URL to prepend to relative paths
    # @return [String] Content with resolved URLs
    def resolve_relative_urls(content, base_url)
      return content unless base_url

      # Match src="./path" or src="path" (not starting with http/https/data//)
      content.gsub(%r{(\ssrc=["'])(\./)?((?!https?:|data:|//)[^"']+)(["'])}) do
        prefix = ::Regexp.last_match(1)
        _dot_slash = ::Regexp.last_match(2)
        path = ::Regexp.last_match(3)
        suffix = ::Regexp.last_match(4)
        "#{prefix}#{base_url}/#{path}#{suffix}"
      end
    end

    # Get category for a URL based on domain patterns
    def category_for_url(url)
      case url
      when %r{docs\.google\.com/(document|spreadsheets|presentation)}
        "Documentation"
      when /github\.com|gitlab/
        "Code Repository"
      when /confluence\.|atlassian\.net/
        "Documentation"
      when /jira\.|atlassian\.net.*jira/
        "Project Management"
      when /grafana/
        "Monitoring"
      when /prometheus/
        "Monitoring"
      when /api\./
        "API"
      when /docs\./
        "Documentation"
      else
        "Other"
      end
    end

    # Sort instances by multiple fields
    # @param instances [Array] Array of resource instances to sort
    # @param sort_fields [Array<String>] Fields to sort by, prefix with '-' for descending
    # @return [Array] Sorted instances
    def sort_instances(instances, sort_fields)
      return instances if sort_fields.empty?

      instances.sort do |a, b|
        cmp = 0
        sort_fields.each do |sort_spec|
          break if cmp != 0

          desc = sort_spec.start_with?("-")
          field = desc ? sort_spec[1..] : sort_spec

          val_a = instance_sort_value(a, field)
          val_b = instance_sort_value(b, field)

          cmp = compare_values(val_a, val_b)
          cmp = -cmp if desc
        end
        cmp
      end
    end

    # Get the value of a field from an instance for sorting
    def instance_sort_value(instance, field)
      case field
      when "name" then instance.name.to_s
      when "kind" then instance.klass.to_s
      else instance.annotations[field]
      end
    end

    # Compare two values, using numeric comparison when both are integers
    def compare_values(val_a, val_b)
      if val_a.to_s.match?(/\A-?\d+\z/) && val_b.to_s.match?(/\A-?\d+\z/)
        val_a.to_i <=> val_b.to_i
      else
        (val_a || "").to_s.downcase <=> (val_b || "").to_s.downcase
      end
    end
  end
end
