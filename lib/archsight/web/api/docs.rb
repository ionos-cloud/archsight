# frozen_string_literal: true

require "sinatra/base"
require "sinatra/extension"

module Archsight; end
module Archsight::Web; end
module Archsight::Web::API; end

# Documentation UI for the REST API
module Archsight::Web::API::Docs
  extend Sinatra::Extension

  get "/api/docs" do
    erb :api_docs
  end
end
