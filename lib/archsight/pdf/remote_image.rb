# frozen_string_literal: true

require "net/http"
require "resolv"
require "ipaddr"
require "uri"
require_relative "../user_config"

module Archsight
  module Pdf
    # Images that a page embeds by URL (`![](https://...)`), fetched by the server so they can go into the PDF.
    #
    # The URL comes from page content, so the server must not become a way into the network behind it: only http(s) on
    # the default ports, only hosts that resolve to public addresses (checked for the address that is connected to, and
    # again for every redirect), a size and time limit, and the answer must really be a png, jpeg, gif or webp image.
    # Anything else is `nil` and the document shows the alt text. `pdf.remote_images: false`
    # (`ARCHSIGHT_PDF_REMOTE_IMAGES`) turns fetching off.
    module RemoteImage
      MAX_BYTES = 10 * 1024 * 1024
      TIMEOUT = 10
      MAX_REDIRECTS = 3
      CACHE_SECONDS = 3600
      CACHE_ENTRIES = 64
      PORTS = { "http" => 80, "https" => 443 }.freeze
      NON_PUBLIC = %w[
        0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
        198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 fc00::/7 fe80::/10 ff00::/8
      ].map { |range| IPAddr.new(range) }.freeze
      TYPES = { png: ".png", jpeg: ".jpg", gif: ".gif", webp: ".webp" }.freeze

      @cache = {}
      @lock = Mutex.new

      class << self
        # @return [Boolean] whether fetching is on
        def enabled?(env: ENV)
          !%w[false no 0 off].include?(UserConfig.setting("pdf", "remote_images", env: env).to_s.strip.downcase)
        end

        # @return [Array(String, String), nil] image bytes and the file extension, nil if it cannot be had
        def fetch(url, resolver: Resolv, now: Time.now)
          cached(url, now) { download(url, resolver) }
        rescue StandardError
          nil
        end

        # Public addresses only: not loopback, private, link-local (cloud metadata), multicast, reserved or unspecified
        def public_address?(address)
          ip = IPAddr.new(address.to_s)
          ip = ip.native if ip.ipv4_mapped?
          NON_PUBLIC.none? { |range| range.include?(ip) }
        rescue IPAddr::Error
          false
        end

        # @return [Symbol, nil] :png, :jpeg, :gif or :webp from the first bytes
        def image_type(bytes)
          head = bytes.byteslice(0, 12).to_s.b
          return :png if head.start_with?("\x89PNG\r\n\x1a\n".b)
          return :jpeg if head.start_with?("\xFF\xD8\xFF".b)
          return :gif if head.start_with?("GIF87a", "GIF89a")

          :webp if head.start_with?("RIFF") && head.byteslice(8, 4) == "WEBP"
        end

        private

        def cached(url, now)
          entry = @lock.synchronize { @cache[url] }
          return entry[:value] if entry && now - entry[:at] < CACHE_SECONDS

          value = yield
          @lock.synchronize do
            @cache[url] = { value: value, at: now }
            @cache.shift while @cache.size > CACHE_ENTRIES
          end
          value
        end

        def download(url, resolver, redirects = 0)
          uri = URI.parse(url)
          return nil unless PORTS.key?(uri.scheme) && uri.host && uri.port == PORTS[uri.scheme] && uri.userinfo.nil?

          addresses = resolver.getaddresses(uri.host).map(&:to_s)
          return nil if addresses.empty? || !addresses.all? { |a| public_address?(a) }

          response, body = get(uri, addresses.first)
          case response
          when Net::HTTPSuccess then image(body)
          when Net::HTTPRedirection
            redirects < MAX_REDIRECTS ? download(URI.join(url, response["location"].to_s).to_s, resolver, redirects + 1) : nil
          end
        end

        # Connects to the address that was checked (not to a second DNS answer); the certificate is checked for the name.
        # @return [Array(Net::HTTPResponse, String), nil] the response and its body, nil if the body is too large
        def get(uri, address)
          http = Net::HTTP.new(uri.host, uri.port)
          http.ipaddr = address
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = http.read_timeout = http.write_timeout = TIMEOUT
          http.request(Net::HTTP::Get.new(uri.request_uri, "Accept" => "image/*", "User-Agent" => "archsight-pdf")) do |res|
            return [res, nil] unless res.is_a?(Net::HTTPSuccess)
            return nil if res["Content-Length"].to_i > MAX_BYTES

            body = +"".b
            res.read_body do |chunk|
              body << chunk
              return nil if body.bytesize > MAX_BYTES
            end
            return [res, body]
          end
        end

        def image(bytes)
          type = image_type(bytes.to_s)
          type ? [bytes, TYPES.fetch(type)] : nil
        end
      end
    end
  end
end
