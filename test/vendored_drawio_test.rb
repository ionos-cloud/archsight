# frozen_string_literal: true

require "test_helper"
require "rack/test"
require "archsight/web/application"

# The draw.io viewer is vendored into the app (lib/archsight/web/public/vendor/drawio) and must work without
# reaching any other host. These tests also notice when the directory goes missing, e.g. when a frontend build
# empties the static directory.
class VendoredDrawioTest < Minitest::Test
  include Rack::Test::Methods

  DIR = File.expand_path("../lib/archsight/web/public/vendor/drawio", __dir__)

  REQUIRED = %w[
    VERSION LICENSE viewer.html viewer-config.js viewer-host.js viewer-static.min.js math-disabled/startup.js
    styles/default.xml shapes stencils/kubernetes2.xml stencils/aws4.xml img/lib/atlassian/Confluence_Logo.svg
    resources/dia.txt mxgraph/images
  ].freeze

  def app = Archsight::Web::Application

  def setup
    Archsight.resources_dir = File.expand_path("../examples/archsight", __dir__)
    app.database.verbose = false
    app.database.reload!
  end

  def read(name) = File.read(File.join(DIR, name))

  def test_the_viewer_and_everything_it_loads_is_there
    REQUIRED.each { |name| assert_path_exists File.join(DIR, name), name }
    assert_operator Dir.glob(File.join(DIR, "stencils/*.xml")).size, :>=, 30
  end

  def test_version_is_an_upstream_tag_and_the_license_is_apache
    assert_match(/\Av\d+\.\d+\.\d+\n\z/, read("VERSION"))
    assert_includes read("LICENSE"), "Apache License"
  end

  def test_the_app_serves_the_viewer_and_its_files
    ["viewer.html", "viewer-config.js", "viewer-host.js", "viewer-static.min.js", "stencils/kubernetes2.xml", "styles/default.xml",
     "img/lib/atlassian/Confluence_Logo.svg", "resources/dia.txt", "math-disabled/startup.js"].each do |name|
      get "/vendor/drawio/#{name}"

      assert_predicate last_response, :ok?, name
    end
  end

  def test_the_big_files_are_compressed_and_the_api_is_not
    get "/vendor/drawio/viewer-static.min.js", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }

    assert_equal "gzip", last_response.headers["Content-Encoding"]
    assert_operator last_response.body.bytesize, :<, File.size(File.join(DIR, "viewer-static.min.js")) / 2

    get "/api/v1/kinds", {}, { "HTTP_ACCEPT_ENCODING" => "gzip" }

    assert_nil last_response.headers["Content-Encoding"]
  end

  def test_the_host_page_forbids_requests_to_other_hosts
    policy = read("viewer.html")[/Content-Security-Policy" content="([^"]*)"/, 1]

    refute_nil policy
    assert_includes policy, "default-src 'none'"
    assert_includes policy, "connect-src 'self'"
    assert_includes policy, "img-src 'self' data: blob:"
    refute_match(%r{https?://|\*}, policy)
    refute_includes policy, "unsafe-eval"
  end

  def test_our_own_files_mention_no_external_url
    %w[viewer.html viewer-config.js viewer-host.js math-disabled/startup.js].each do |name|
      refute_match(%r{(?:https?|wss?)://}, read(name).gsub(%r{xmlns="http://www\.w3\.org/[^"]*"}, ""), name)
    end
  end

  # viewer-static.min.js only sets a path or URL when it is undefined, and then to viewer.diagrams.net,
  # app.diagrams.net, github.com... Every such setting must be overridden in viewer-config.js.
  def test_every_external_default_of_the_viewer_is_overridden
    defaults = read("viewer-static.min.js").scan(/window\.(\w+)=window\.\1\|\|([^;]*)/)
    external = defaults.select { |_, value| value.match?(%r{(?:https?|wss?)://(?!www\.w3\.org)}) }.map(&:first).uniq
    config = read("viewer-config.js")

    refute_empty external, "the pattern should find the defaults of the current viewer"
    missing = external.reject { |name| config.match?(/window\.#{Regexp.escape(name)}\s*=/) }

    assert_empty missing, "viewer-config.js must set #{missing.join(", ")}: upstream defaults them to an external host"
  end
end
