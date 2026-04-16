# frozen_string_literal: true

require "sinatra/base"
require "kramdown"
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
require_relative "api/routes"
require_relative "api/docs"
require_relative "editor/routes"

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

    # Configure application for the given environment
    # @param env [Symbol] :development or :production
    # @param logging [Boolean, nil] Override default logging setting
    def configure_environment!(env, logging: nil)
      set :environment, env

      if env == :production
        set :quiet, true
        set :server_settings, { Silent: true }
      end

      # Determine logging: CLI override > env default (prod=true, dev=false)
      enable_logging = logging.nil? ? (env == :production) : logging
      use Rack::CommonLogger, $stdout if enable_logging
    end
  end

  configure do
    set :public_folder, File.join(__dir__, "public")
    set :server, :puma
    set :reload_enabled, true
    set :inline_edit_enabled, false
    set :restart_enabled, false
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
    mcp_server.register_tool(Archsight::MCP::ExecuteAnalysisTool)

    use FastMcp::Transports::RackTransport, mcp_server,
        path_prefix: "/mcp",
        localhost_only: false
  end

  helpers Archsight::GraphvisRenderer, Archsight::Helpers

  # Register API modules
  register Archsight::Web::API::Routes
  register Archsight::Web::API::Docs
  register Archsight::Web::Editor::Routes

  helpers do
    def db
      Archsight::Web::Application.database
    end

    def reload_enabled?
      settings.reload_enabled
    end

    def inline_edit_enabled?
      settings.inline_edit_enabled
    end

    def restart_enabled?
      settings.restart_enabled
    end

    def production?
      settings.environment == :production
    end

    def development?
      settings.environment == :development
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

    # Wrapper for render_analysis_section that provides markdown renderer
    def render_analysis_section(section)
      Archsight::Helpers.render_analysis_section(section, markdown_renderer: method(:markdown))
    end

    # Serve the Vue SPA shell (built by Vite)
    def serve_vue
      vue_path = File.join(settings.public_folder, "vue.html")
      content_type :html
      if File.exist?(vue_path)
        File.read(vue_path)
      else
        "<!DOCTYPE html><html><body><p>Vue frontend not built. Run: cd frontend &amp;&amp; npm run build</p></body></html>"
      end
    end
  end

  get "/" do
    serve_vue
  end

  get "/reload" do
    halt 404, "Reload is disabled" unless settings.reload_enabled

    Archsight::Web::Application.reload!
    if request.env["HTTP_ACCEPT"]&.include?("application/json") || request.xhr?
      content_type :json
      JSON.generate({ ok: true })
    elsif params["redirect"]&.start_with?("/")
      redirect params["redirect"]
    else
      redirect "/"
    end
  rescue Archsight::ResourceError => e
    if request.env["HTTP_ACCEPT"]&.include?("application/json") || request.xhr?
      content_type :json
      status 422
      JSON.generate({
                      error: e.message,
                      path: relative_error_path(e.ref.path),
                      line_no: e.ref.line_no,
                      context: error_context_lines(e.ref.path, e.ref.line_no)
                    })
    else
      content_type :html
      path = ERB::Util.html_escape(relative_error_path(e.ref.path))
      msg = ERB::Util.html_escape(e.message)
      "<!DOCTYPE html><html><body><h3>Error: #{msg}</h3><p>#{path} line #{e.ref.line_no}</p><a href='/'>Back</a></body></html>"
    end
  end

  def self.perform_restart!
    Thread.new do
      sleep 0.5
      Process.kill("TERM", Process.pid)
    end
  end

  post "/maintenance/restart" do
    halt 404, "Restart endpoint is disabled" unless settings.restart_enabled
    Archsight::Web::Application.perform_restart!
    content_type :json
    JSON.generate({ ok: true, message: "Server shutting down" })
  end

  get "/doc/resources/:filename" do
    serve_vue
  end

  get "/doc/:filename" do
    serve_vue
  end

  # GET /search - for direct URL access, Vue SPA handles rendering
  get "/search" do
    serve_vue
  end

  get "/dot" do
    content_type "text/plain"
    create_graph_all(db)
  end

  get "/kinds/:kind" do
    serve_vue
  end

  get "/kinds/:kind/instances/:instance" do
    serve_vue
  end

  get "/kinds/:kind/instances/:instance/dot" do
    @kind = params["kind"]
    @instance = params["instance"]
    content_type "text/plain"
    create_graph_one(db, @kind, @instance)
  end
end
