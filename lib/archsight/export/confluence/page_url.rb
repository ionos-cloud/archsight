# frozen_string_literal: true

require "uri"
require "cgi"

module Archsight
  module Export
    module Confluence
      # The location of a Confluence (Data Center) page, from the URL a wiki page carries in `confluence:`.
      #
      #   https://host/spaces/KEY/pages/12345/Title            (page id)
      #   https://host/confluence/pages/viewpage.action?pageId=12345   (context path, page id)
      #   https://host/display/KEY/Title                        (space and title, the id is looked up)
      PageUrl = Struct.new(:base, :page_id, :space, :title, keyword_init: true) do
        def self.parse(url)
          uri = begin
            URI.parse(url.to_s.strip)
          rescue URI::InvalidURIError
            raise ArgumentError, "not a URL: #{url.inspect}"
          end
          raise ArgumentError, "not an http(s) URL: #{url.inspect}" unless uri.is_a?(URI::HTTP) && uri.host

          origin = "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}"
          path = uri.path.to_s
          from_path(origin, path, uri.query) ||
            raise(ArgumentError, "cannot find a Confluence page in #{url.inspect} " \
                                 "(expected .../spaces/KEY/pages/ID/..., .../pages/viewpage.action?pageId=ID or .../display/KEY/Title)")
        end

        def self.from_path(origin, path, query)
          if (m = path.match(%r{\A(?<ctx>.*?)/spaces/(?<space>[^/]+)/pages/(?<id>\d+)}))
            new(base: origin + m[:ctx], page_id: m[:id], space: CGI.unescape(m[:space]))
          elsif (m = path.match(%r{\A(?<ctx>.*?)/pages/viewpage\.action\z})) && (id = CGI.parse(query.to_s)["pageId"].first)&.match?(/\A\d+\z/)
            new(base: origin + m[:ctx], page_id: id)
          elsif (m = path.match(%r{\A(?<ctx>.*?)/display/(?<space>[^/]+)/(?<title>[^/]+)\z}))
            new(base: origin + m[:ctx], space: CGI.unescape(m[:space]), title: CGI.unescape(m[:title]))
          end
        end

        # URL to open a page by id
        def view_url(id = page_id)
          "#{base}/pages/viewpage.action?pageId=#{id}"
        end
      end
    end
  end
end
