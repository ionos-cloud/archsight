# frozen_string_literal: true

require "sinatra/base"
require "sinatra/extension"

module Archsight; end
module Archsight::Web; end
module Archsight::Web::API; end

# Documentation UI for the REST API
module Archsight::Web::API::Docs
  extend Sinatra::Extension

  get "/docs/api" do
    serve_vue
  end

  # GET /api/v1/docs/resources/:filename — auto-generated resource docs
  get "/api/v1/docs/resources/:filename" do
    filename = params["filename"].gsub(/[^a-zA-Z0-9_-]/, "")
    kind_name = filename.split("_").map(&:capitalize).join

    begin
      content = Archsight::Documentation.generate(kind_name)
      content_type :html
      "<article>#{markdown(content)}</article>"
    rescue StandardError
      halt 404, "Documentation not found"
    end
  end

  # GET /api/v1/docs/:filename — static markdown/ERB docs
  get "/api/v1/docs/:filename" do
    filename = params["filename"].gsub(/[^a-zA-Z0-9_-]/, "")

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

    content_type :html
    "<article>#{markdown(content)}</article>"
  end
end
