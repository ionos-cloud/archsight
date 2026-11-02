# frozen_string_literal: true

require_relative "../../pdf"
require_relative "../../pdf/cache"
require_relative "../../pdf/sample_document"

module Archsight; end
module Archsight::Web; end
module Archsight::Web::API; end

# Download of a page or resource as PDF
module Archsight::Web::API::PdfHelpers
  CACHE = Archsight::Pdf::Cache.new
  COMPILER = Archsight::Pdf::Compiler.new

  # Sends the PDF of `resource`. The ETag is the fingerprint of everything the PDF is made from, so a client (and
  # the server's cache) keeps it exactly as long as the page, its images, diagrams and the template are unchanged.
  # Query: `template` (name of a pdf Config), `draft=1` (watermark).
  def serve_pdf(resource)
    pdf_response do
      Archsight::Pdf.document(db, resource, compiler: COMPILER, template: params[:template].to_s.empty? ? nil : params[:template],
                                            draft: params[:draft] == "1")
    end
  end

  # Sends the sample document in the look of a pdf Config, shown in the page instead of downloaded
  def serve_pdf_preview(config)
    pdf_response("inline") { Archsight::Pdf::SampleDocument.new(db, config, part: params[:part], pdf_images: COMPILER.pdf_images?) }
  end

  # Typesets the document the block builds and sends it; typst problems are answered as JSON errors
  def pdf_response(disposition = "attachment")
    document = yield
    headers "X-Content-Type-Options" => "nosniff"
    cache_control :private, :must_revalidate, max_age: 0
    etag document.fingerprint
    pdf = CACHE.fetch(document.fingerprint) { Archsight::Pdf.compile(document, compiler: COMPILER) }
    content_type "application/pdf"
    headers "Content-Disposition" => %(#{disposition}; filename="#{document.filename}")
    pdf
  rescue Archsight::Pdf::Unavailable => e
    json_error(e.message, status: 503, error_type: "ServiceUnavailable")
  rescue Archsight::Pdf::Error => e
    json_error(e.message, status: 422, error_type: "UnprocessableEntity")
  end
end
