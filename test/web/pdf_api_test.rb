# frozen_string_literal: true

require "test_helper"
require "rack/test"
require "json"
require "archsight/web/application"

class PdfAPITest < Minitest::Test
  include Rack::Test::Methods

  def app
    Archsight::Web::Application
  end

  def setup
    Archsight.resources_dir = File.expand_path("../../examples/archsight", __dir__)
    Archsight::Web::Application.database.verbose = false
    Archsight::Web::Application.database.reload!
  end

  # Makes Archsight::Pdf.document raise `error` for the block
  def with_failing_document(error)
    original = Archsight::Pdf.method(:document)
    Archsight::Pdf.define_singleton_method(:document) { |*_args, **_opts| raise error }
    yield
  ensure
    Archsight::Pdf.define_singleton_method(:document, original)
  end

  def typst?
    system("typst", "--version", out: File::NULL, err: File::NULL)
  end

  def test_page_as_pdf
    skip "typst is not installed" unless typst?

    get "/api/v1/pages/diagrams-in-pages/pdf"

    assert_predicate last_response, :ok?
    assert_equal "application/pdf", last_response.content_type
    assert_match(/\Aattachment; filename="diagrams-in-pages\.pdf"\z/, last_response.headers["Content-Disposition"])
    assert_equal "nosniff", last_response.headers["X-Content-Type-Options"]
    assert last_response.body.start_with?("%PDF")
  end

  def test_resource_as_pdf_and_conditional_request
    skip "typst is not installed" unless typst?

    get "/api/v1/kinds/ApplicationComponent/instances/Archsight:Web:API/pdf"

    assert_predicate last_response, :ok?
    etag = last_response.headers["ETag"]

    refute_nil etag

    get "/api/v1/kinds/ApplicationComponent/instances/Archsight:Web:API/pdf", {}, { "HTTP_IF_NONE_MATCH" => etag }

    assert_equal 304, last_response.status
  end

  def test_unknown_page_kind_and_instance_are_not_found
    get "/api/v1/pages/nope/pdf"

    assert_equal 404, last_response.status

    get "/api/v1/kinds/Nope/instances/x/pdf"

    assert_equal 404, last_response.status

    get "/api/v1/kinds/ApplicationComponent/instances/nope/pdf"

    assert_equal 404, last_response.status
  end

  def test_missing_typst_is_service_unavailable
    with_failing_document(Archsight::Pdf::Unavailable.new("typst is not installed")) do
      get "/api/v1/pages/diagrams-in-pages/pdf"
    end

    assert_equal 503, last_response.status
    assert_equal "ServiceUnavailable", JSON.parse(last_response.body)["error"]
  end

  def test_typst_failure_is_unprocessable
    with_failing_document(Archsight::Pdf::Error.new("typst failed")) do
      get "/api/v1/pages/diagrams-in-pages/pdf"
    end

    assert_equal 422, last_response.status
  end

  def test_config_preview_is_an_inline_sample_in_the_look_of_the_config
    skip "typst is not installed" unless typst?

    get "/api/v1/kinds/Config/instances/Config:PDF:default/preview"

    assert_predicate last_response, :ok?
    assert_equal "application/pdf", last_response.content_type
    assert_match(/\Ainline; filename="preview-/, last_response.headers["Content-Disposition"])
    assert last_response.body.start_with?("%PDF")

    etag = last_response.headers["ETag"]
    get "/api/v1/kinds/Config/instances/Config:PDF:default/preview", {}, { "HTTP_IF_NONE_MATCH" => etag }

    assert_equal 304, last_response.status
  end

  def test_config_preview_rejects_unknown_and_non_pdf_configs
    get "/api/v1/kinds/Config/instances/nope/preview"

    assert_equal 404, last_response.status
  end
end
