# frozen_string_literal: true

require "erb"
require "open3"
require "pathname"
require "uri"

module Archsight
  # Where a file lives in its git repository and its page in the web UI of the git host, for links to the source of
  # generated content (the banner of an exported Confluence page). Only local git is asked (the repository of the
  # file, its `origin` remote, the checked out branch), nothing goes over the network.
  #
  # The web URL is `https://<host>/<owner>/<repo>` of the remote, without the user, password or token a remote URL
  # may carry. GitHub files are `/blob/<ref>/<path>`, GitLab files `/-/blob/<ref>/<path>`; on other hosts, and for a
  # file git does not track, only the repository is linked. The ref is the checked out branch, the commit when the
  # HEAD is detached (CI).
  module GitSource
    # repository: "owner/repo"; repository_url: its web page; path: the file relative to the repository root;
    # url: the web page of the file, nil if the host is not known
    Location = Struct.new(:repository, :repository_url, :path, :url, keyword_init: true)

    module_function

    # @param file [String] path of a file
    # @return [Location, nil] nil if the file is not in a git repository with an `origin` remote
    def locate(file)
      dir = File.dirname(File.expand_path(file))
      root = git(dir, "rev-parse", "--show-toplevel") or return nil
      remote = git(dir, "remote", "get-url", "origin") or return nil
      host, repository = host_and_repository(remote)
      return nil unless host && repository

      path = Pathname.new(File.realpath(file)).relative_path_from(Pathname.new(File.realpath(root))).to_s
      ref = git(dir, "symbolic-ref", "--short", "-q", "HEAD") || git(dir, "rev-parse", "HEAD")
      repository_url = "https://#{host}/#{repository}"
      url = tracked?(root, path) ? file_url(host, repository_url, ref, path) : nil
      Location.new(repository: repository, repository_url: repository_url, path: path, url: url)
    rescue SystemCallError, ArgumentError
      nil
    end

    # `git@host:owner/repo.git`, `ssh://git@host:22/owner/repo.git`, `https://user:token@host/owner/repo` ->
    # ["host", "owner/repo"]; the port of an ssh remote is not the port of the web UI and is left out
    def host_and_repository(remote)
      if (scp = remote.match(%r{\A(?:[^@/\s]+@)?([^:/\s]+):(?!//)(.+)\z}))
        host, path = scp.captures
      else
        uri = URI.parse(remote)
        return [nil, nil] unless uri.host && %w[http https ssh git].include?(uri.scheme)

        host = uri.scheme.start_with?("http") && uri.port != uri.default_port ? "#{uri.host}:#{uri.port}" : uri.host
        path = uri.path
      end
      repository = path.delete_prefix("/").delete_suffix("/").delete_suffix(".git")
      repository.empty? ? [nil, nil] : [host, repository]
    rescue URI::InvalidURIError
      [nil, nil]
    end

    def file_url(host, repository_url, ref, path)
      blob = if host.match?(/(\A|\.)github\./) then "blob"
             elsif host.match?(/(\A|\.)gitlab\./) then "-/blob"
             end
      return nil unless blob && ref

      "#{repository_url}/#{blob}/#{escape(ref)}/#{escape(path)}"
    end

    # An untracked or ignored file is not on the git host: no link that leads nowhere
    def tracked?(root, path) = !git(root, "ls-files", "--", path).nil?

    # each segment escaped, the slashes kept
    def escape(path) = path.split("/").map { |segment| ERB::Util.url_encode(segment) }.join("/")

    def git(dir, *)
      out, _err, status = Open3.capture3("git", "-C", dir, *)
      value = out.strip
      status.success? && !value.empty? ? value : nil
    end
  end
end
