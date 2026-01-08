# frozen_string_literal: true

require "sinatra/base"
require "kramdown"
require "haml"
require "erb"
require "fast_mcp"

require_relative "../database"
require_relative "../graph"
require_relative "../renderer"
require_relative "../helpers"
require_relative "../documentation"
require_relative "../query"
require_relative "../resources"
require_relative "../mcp"

# Define the Web namespace before the class definition
module Archsight::Web; end

class Archsight::Web::Application < Sinatra::Base
  class << self
    attr_accessor :db

    def database
      @database ||= Archsight::Database.new(Archsight.resources_dir).tap(&:reload!)
    end

    def reload!
      start = Time.new
      puts "== Reloading ..." if database.verbose
      database.reload!
      dur = (Time.new - start) * 1000
      puts format("== done %0.2f ms", dur) if database.verbose
    end
  end

  configure do
    set :views, File.join(__dir__, "views")
    set :public_folder, File.join(__dir__, "public")
    set :haml, format: :html5
    set :server, :puma
  end

  # MCP Server setup
  def self.setup_mcp!
    mcp_server = FastMcp::Server.new(
      name: "Archsight MCP",
      version: Archsight::VERSION
    )

    # Configure MCP tools with database
    Archsight::MCP.db = database

    mcp_server.register_tool(Archsight::MCP::QueryTool)
    mcp_server.register_tool(Archsight::MCP::AnalyzeResourceTool)
    mcp_server.register_tool(Archsight::MCP::ResourceDocTool)

    use FastMcp::Transports::RackTransport, mcp_server,
        path_prefix: "/mcp",
        localhost_only: false
  end

  helpers Archsight::GraphvisHelper, Archsight::GraphvisRenderer, Archsight::Helpers

  helpers do
    def db
      Archsight::Web::Application.database
    end

    # Render markdown to HTML with optional URL resolution for repository content
    # @param data [String] Markdown content
    # @param git_url [String, nil] Git URL for resolving relative paths (e.g., for README images)
    def markdown(data, git_url: nil)
      html = Kramdown::Document.new(data, input: "GFM").to_html

      # Resolve relative URLs if we have a git URL (for repository READMEs)
      if git_url && (base_url = github_raw_base_url(git_url))
        html = resolve_relative_urls(html, base_url)
      end

      # Auto-link bare URLs that aren't already inside HTML attributes or anchor tags
      html = html.gsub(%r{(?<!=["'])(?<!">)(https?://[^\s<>"]+)}) do |match|
        # Strip trailing punctuation that's likely sentence-ending, not part of URL
        url = match.sub(/[.,;:!)]+$/, "")
        trailing = match[url.length..]
        %(<a href="#{url}">#{url}</a>#{trailing})
      end
      # Convert [[ResourceName]] wiki-style links to resource links
      html.gsub(/\[\[([^\]]+)\]\]/) do |_match|
        name = ::Regexp.last_match(1)
        resource = db.query("name =~ \"#{name}\"").first
        if resource
          %(<a href="/kinds/#{resource.kind}/instances/#{resource.name}">#{name}</a>)
        else
          %(<span class="broken-link" title="Resource not found">#{name}</span>)
        end
      end
    end

    def to_dollar(num)
      # Round to 2 decimals first (important for floating‑point edge cases)
      rounded = (num * 100).round / 100.0
      # Insert commas every three digits left of the decimal point
      parts = format("%.2f", rounded).split(".")
      parts[0] = parts[0].reverse.scan(/\d{1,3}/).join(",").reverse
      "$#{parts.join(".")}"
    end

    def http_git(repo_url)
      repo_url.gsub(/.git$/, "")
              .gsub(":", "/")
              .gsub("git@", "https://")
    end

    def number_with_delimiter(num)
      num.to_s.reverse.scan(/\d{1,3}/).join(",").reverse
    end

    # Generate asset path with cache-busting query string based on file mtime
    def asset_path(path)
      file_path = File.join(settings.public_folder, path)
      if File.exist?(file_path)
        mtime = File.mtime(file_path).to_i
        "#{path}?v=#{mtime}"
      else
        path
      end
    end

    # Convert timestamp to human-readable relative time
    def time_ago(timestamp)
      return nil unless timestamp

      time = timestamp.is_a?(Time) ? timestamp : Time.parse(timestamp.to_s)
      seconds = (Time.now - time).to_i

      units = [
        [60, "second"],
        [60, "minute"],
        [24, "hour"],
        [7, "day"],
        [4, "week"],
        [12, "month"],
        [Float::INFINITY, "year"]
      ]

      value = seconds
      units.each do |divisor, unit|
        return "just now" if unit == "second" && value < 10
        return "#{value} #{unit}#{"s" if value != 1} ago" if value < divisor

        value /= divisor
      end
    end
  end

  get "/" do
    haml :index
  end

  get "/reload" do
    Archsight::Web::Application.reload!
    if params["redirect"]&.start_with?("/")
      redirect params["redirect"]
    else
      redirect "/"
    end
  rescue Archsight::ResourceError => e
    @error = e
    haml :index
  end

  get "/doc/resources/:filename" do
    filename = params["filename"].gsub(/[^a-zA-Z0-9_-]/, "") # sanitize
    # Convert snake_case to PascalCase for resource kind
    kind_name = filename.split("_").map(&:capitalize).join

    begin
      content = Archsight::Documentation.generate(kind_name)
      @doc_content = markdown(content)
    rescue StandardError
      halt 404, "Documentation not found"
    end

    if request.env["HTTP_HX_REQUEST"]
      "<article>#{@doc_content}</article>"
    else
      haml :index
    end
  end

  get "/doc/:filename" do
    filename = params["filename"].gsub(/[^a-zA-Z0-9_-]/, "") # sanitize

    # Check for ERB template first, then plain markdown
    erb_path = File.join(settings.views, "..", "doc", "#{filename}.md.erb")
    md_path = File.join(settings.views, "..", "doc", "#{filename}.md")

    content = if File.exist?(erb_path)
                template = ERB.new(File.read(erb_path))
                template.result(binding)
              elsif File.exist?(md_path)
                File.read(md_path)
              else
                halt 404, "Documentation not found"
              end

    @doc_content = markdown(content)

    if request.env["HTTP_HX_REQUEST"]
      "<article>#{@doc_content}</article>"
    else
      haml :index
    end
  end

  # Shared search logic for both GET and POST
  def perform_search
    start_time = Time.now
    if (@q = params["q"])
      @instances = db.query(@q)
    elsif (@tag = params["tag"]) && (@value = params["value"])
      @method = params["method"] || "=="
      # Build query string - quote value for string operators, leave unquoted for numeric
      quoted_value = if %w[> < >= <=].include?(@method)
                       @value # Numeric comparison, no quotes
                     else
                       "\"#{@value.gsub('"', '\\"')}\"" # String comparison, quote it
                     end
      @q = "#{@tag} #{@method} #{quoted_value}"
      @instances = db.query(@q)
    else
      @instances = []
    end
    if (@kind = params["kind"])
      @instances = @instances.select { |i| i.kind == @kind } if @kind
    end
    @search_time_ms = ((Time.now - start_time) * 1000).round(2)
  rescue Archsight::Query::QueryError => e
    @query_error = e
    @search_time_ms = ((Time.now - start_time) * 1000).round(2)
    @q = params["q"] || "#{params["tag"]} #{params["method"] || "=="} \"#{params["value"]}\""
  end

  # GET /search - for direct URL access, bookmarks, and browser history
  get "/search" do
    perform_search
    haml :index
  end

  # POST /search - for HTMX requests
  post "/search" do
    perform_search
    haml :search
  end

  get "/svg" do
    content_type :svg
    create_graph_all(db, :draw_svg)
  end

  get "/dot" do
    content_type "text/plain"
    create_graph_all(db, :draw_dot)
  end

  get "/kinds/:kind" do
    @kind = params["kind"]
    haml :index
  end

  get "/kinds/:kind/instances/:instance" do
    @kind = params["kind"]
    @instance = params["instance"]
    haml :index
  end

  get "/kinds/:kind/instances/:instance/svg" do
    @kind = params["kind"]
    @instance = params["instance"]
    content_type :svg
    create_graph_one(db, @kind, @instance, :draw_svg)
  end

  get "/kinds/:kind/instances/:instance/dot" do
    @kind = params["kind"]
    @instance = params["instance"]
    content_type "text/plain"
    create_graph_one(db, @kind, @instance, :draw_dot)
  end
end
