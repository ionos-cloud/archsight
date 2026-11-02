# frozen_string_literal: true

require_relative "pdf_fixture"

class PdfRemoteImageTest < Minitest::Test
  include PdfFixture

  RemoteImage = Archsight::Pdf::RemoteImage

  def setup = build_resources
  def teardown = cleanup_resources

  def test_only_public_addresses_are_allowed
    %w[8.8.8.8 93.184.216.34 2606:4700::1111].each { |a| assert RemoteImage.public_address?(a), "#{a} should be public" }
    %w[127.0.0.1 10.1.2.3 172.16.0.1 192.168.1.1 169.254.169.254 100.64.0.1 0.0.0.0 224.0.0.1 ::1 fe80::1 fd00::1
       ::ffff:127.0.0.1 not-an-ip].each { |a| refute RemoteImage.public_address?(a), a }
  end

  def test_the_type_comes_from_the_bytes_not_from_the_url
    assert_equal :png, RemoteImage.image_type("\x89PNG\r\n\x1a\nrest".b)
    assert_equal :jpeg, RemoteImage.image_type("\xFF\xD8\xFFrest".b)
    assert_equal :gif, RemoteImage.image_type("GIF89arest")
    assert_equal :webp, RemoteImage.image_type("RIFF\x00\x00\x00\x00WEBPrest".b)
    assert_nil RemoteImage.image_type("<svg xmlns='http://www.w3.org/2000/svg'/>")
    assert_nil RemoteImage.image_type("<html>")
  end

  def test_private_hosts_and_other_schemes_are_never_requested
    resolver = Class.new { def self.getaddresses(_host) = ["127.0.0.1"] }

    assert_nil RemoteImage.fetch("http://localhost/a.png", resolver: resolver)
    assert_nil RemoteImage.fetch("file:///etc/passwd", resolver: resolver)
    assert_nil RemoteImage.fetch("https://user:pw@example.com/a.png", resolver: resolver)
    assert_nil RemoteImage.fetch("https://example.com:8443/a.png", resolver: resolver)
  end

  def test_one_private_answer_among_public_ones_blocks_the_host
    resolver = Class.new { def self.getaddresses(_host) = ["93.184.216.34", "10.0.0.5"] }

    assert_nil RemoteImage.fetch("https://rebind.example.com/a.png", resolver: resolver)
  end

  def test_fetching_can_be_switched_off
    assert RemoteImage.enabled?(env: {})
    refute RemoteImage.enabled?(env: { "ARCHSIGHT_PDF_REMOTE_IMAGES" => "false" })
  end

  def test_a_page_image_by_url_is_staged_when_the_fetch_succeeds_and_shows_the_alt_text_when_not
    png = "\x89PNG\r\n\x1a\nxx".b
    fetched = ->(_url) { [png, ".png"] }
    images = Archsight::Pdf::Images.new(base_dir: "", resources_dir: @dir, pdf_images: false, remote: fetched)

    assert_equal '#fit-image("img-1.png")', images.image("https://example.com/a.png")
    assert_equal png, images.files["img-1.png"]

    missing = Archsight::Pdf::Images.new(base_dir: "", resources_dir: @dir, pdf_images: false, remote: ->(_) {})

    assert_nil missing.image("https://example.com/a.png")
    assert_nil Archsight::Pdf::Images.new(base_dir: "", resources_dir: @dir, remote: fetched).image("mailto:x@example.com")
  end
end
