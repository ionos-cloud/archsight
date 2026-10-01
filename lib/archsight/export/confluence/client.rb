# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "securerandom"

module Archsight
  module Export
    module Confluence
      # The few Confluence Data Center REST calls the export needs (`/rest/api`, personal access token as Bearer
      # token). The token is only ever sent in the Authorization header; errors carry the status and the server's
      # message, never the request headers.
      class Client
        class Error < Archsight::Export::Error
          attr_reader :status

          def initialize(message, status: nil)
            super(message)
            @status = status
          end
        end

        # A property of a content (the marker Archsight leaves on a page)
        Property = Struct.new(:value, :version, keyword_init: true)

        # @param base [String] e.g. https://confluence.example.com (with the context path, if any)
        # @param token [#reveal] the personal access token (Credentials::Secret)
        # @param transport [#call, nil] `(method, url, headers, body) -> [status, body]`, for tests
        def initialize(base:, token:, transport: nil)
          @base = base.chomp("/")
          @token = token
          @transport = transport || method(:http_transport)
        end

        attr_reader :base

        # The user the token belongs to ("username", "displayName"); also proves the token works.
        def current_user
          get("/rest/api/user/current")
        end

        def content(id)
          get("/rest/api/content/#{id}", expand: "version,space,body.storage,history.lastUpdated")
        end

        # The id of the page with this title in a space, nil if there is none
        def find_page_id(space, title)
          results = get("/rest/api/content", spaceKey: space, title: title, type: "page")["results"]
          results&.first&.fetch("id", nil)
        end

        # Replace the body of a page; the title and space stay as they are.
        # @return [Hash] the updated content (its "version" => { "number" })
        def update_page(id, title:, space:, body:, version:, message:)
          put("/rest/api/content/#{id}", {
                id: id, type: "page", title: title, space: { key: space },
                body: { storage: { value: body, representation: "storage" } },
                version: { number: version, message: message }
              })
        end

        # @return [Property, nil]
        def property(id, key)
          data = get("/rest/api/content/#{id}/property/#{key}")
          Property.new(value: data["value"], version: data.dig("version", "number"))
        rescue Error => e
          raise unless e.status == 404

          nil
        end

        def save_property(id, key, value, existing)
          if existing
            put("/rest/api/content/#{id}/property/#{key}", { key: key, value: value, version: { number: existing.version + 1 } })
          else
            post("/rest/api/content/#{id}/property", { key: key, value: value })
          end
        end

        # @return [Hash{String => String}] attachment title => attachment id
        def attachments(id)
          results = get("/rest/api/content/#{id}/child/attachment", limit: 500)["results"] || []
          results.to_h { |a| [a["title"], a["id"]] }
        end

        # Add an attachment, or a new version of it when it exists already.
        def upload_attachment(id, filename:, data:, content_type:, existing_id: nil, comment: nil)
          path = existing_id ? "/rest/api/content/#{id}/child/attachment/#{existing_id}/data" : "/rest/api/content/#{id}/child/attachment"
          parts = [["file", data, { filename: filename, content_type: content_type }]]
          parts << ["comment", comment] if comment
          parts << %w[minorEdit true]
          multipart(path, parts)
        end

        def delete_attachment(attachment_id)
          call("DELETE", "/rest/api/content/#{attachment_id}")
        end

        # Let only this user edit the page (best effort: the caller reports a failure).
        def restrict_update_to(id, username)
          put("/rest/api/content/#{id}/restriction", [{ operation: "update", restrictions: { user: [{ type: "known", username: username }] } }])
        end

        private

        def get(path, **query) = call("GET", path, query: query)
        def put(path, payload) = call("PUT", path, payload: payload)
        def post(path, payload) = call("POST", path, payload: payload)

        def call(verb, path, query: {}, payload: nil)
          headers = {}
          body = nil
          if payload
            headers["Content-Type"] = "application/json"
            body = JSON.generate(payload)
          end
          respond(*@transport.call(verb, url(path, query), headers.merge(auth), body))
        end

        def multipart(path, parts)
          boundary = "archsight-#{SecureRandom.hex(12)}"
          body = parts.map { |name, value, file| part(boundary, name, value, file) }.join + "--#{boundary}--\r\n"
          headers = auth.merge("Content-Type" => "multipart/form-data; boundary=#{boundary}", "X-Atlassian-Token" => "no-check")
          respond(*@transport.call("POST", url(path, {}), headers, body.b))
        end

        def part(boundary, name, value, file)
          disposition = %(form-data; name="#{name}")
          disposition += %(; filename="#{file[:filename]}") if file
          head = "--#{boundary}\r\nContent-Disposition: #{disposition}\r\n"
          head += "Content-Type: #{file[:content_type]}\r\n" if file
          "#{head}\r\n".b + value.to_s.b + "\r\n".b
        end

        def auth = { "Authorization" => "Bearer #{@token.reveal}", "Accept" => "application/json" }

        def url(path, query)
          query = query.compact
          "#{@base}#{path}#{"?#{URI.encode_www_form(query)}" unless query.empty?}"
        end

        def respond(status, body)
          return (body.to_s.empty? ? {} : JSON.parse(body)) if status.between?(200, 299)

          raise Error.new("Confluence answered #{status}#{": #{message_of(body)}" if message_of(body)}", status: status)
        end

        def message_of(body)
          JSON.parse(body.to_s)["message"]
        rescue JSON::ParserError
          nil
        end

        def http_transport(verb, url, headers, body)
          uri = URI(url)
          request = Net::HTTP.const_get(verb.capitalize).new(uri)
          headers.each { |k, v| request[k] = v }
          request.body = body if body
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.read_timeout = 120
          response = http.start { |h| h.request(request) }
          [response.code.to_i, response.body]
        end
      end
    end
  end
end
