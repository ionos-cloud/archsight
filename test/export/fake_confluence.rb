# frozen_string_literal: true

require "json"
require "uri"

# An in-memory stand-in for the Confluence REST calls the export makes, used as the Client's transport.
class FakeConfluence
  Page = Struct.new(:id, :title, :space, :version, :by, :at, :body, :properties, :attachments, :restriction, keyword_init: true)

  attr_reader :pages, :requests, :uploads, :deleted
  attr_accessor :restriction_error

  def initialize(token: "secret-token")
    @token = token
    @pages = {}
    @requests = []
    @uploads = []
    @deleted = []
    @next_attachment = 100
  end

  def add_page(id, title: "Test", space: "SP", body: "<p>hello</p>")
    @pages[id.to_s] = Page.new(id: id.to_s, title: title, space: space, version: 1, by: "Original Author", at: "2026-01-01T10:00:00.000Z",
                               body: body, properties: {}, attachments: {}, restriction: nil)
  end

  # Someone edits the page in Confluence
  def edit(id, by:, body: "<p>edited</p>")
    page = @pages.fetch(id.to_s)
    page.version += 1
    page.by = by
    page.at = "2026-02-02T12:00:00.000Z"
    page.body = body
  end

  def call(verb, url, headers, body)
    uri = URI(url)
    @requests << { verb: verb, path: uri.path, headers: headers }
    return [401, JSON.generate(message: "unauthorized")] unless headers["Authorization"] == "Bearer #{@token}"

    route(verb, uri, headers, body)
  end

  private

  def route(verb, uri, headers, body)
    query = URI.decode_www_form(uri.query.to_s).to_h
    case [verb, uri.path]
    in ["GET", "/rest/api/user/current"] then ok(username: "exporter", displayName: "Exporter")
    in ["GET", "/rest/api/content"] then find(query)
    in ["GET", %r{\A/rest/api/content/(\d+)\z}] then page_json(::Regexp.last_match(1))
    in ["PUT", %r{\A/rest/api/content/(\d+)\z}] then update(::Regexp.last_match(1), JSON.parse(body))
    in ["GET", %r{\A/rest/api/content/(\d+)/property/(\w+)\z}] then get_property(::Regexp.last_match(1), ::Regexp.last_match(2))
    in ["POST", %r{\A/rest/api/content/(\d+)/property\z}] then create_property(::Regexp.last_match(1), JSON.parse(body))
    in ["PUT", %r{\A/rest/api/content/(\d+)/property/(\w+)\z}] then update_property(::Regexp.last_match(1), ::Regexp.last_match(2), JSON.parse(body))
    in ["GET", %r{\A/rest/api/content/(\d+)/child/attachment\z}] then list_attachments(::Regexp.last_match(1))
    in ["POST", %r{\A/rest/api/content/(\d+)/child/attachment(?:/(\d+)/data)?\z}] then upload(::Regexp.last_match(1), ::Regexp.last_match(2), headers, body)
    in ["PUT", %r{\A/rest/api/content/(\d+)/restriction\z}] then restrict(::Regexp.last_match(1), JSON.parse(body))
    in ["DELETE", %r{\A/rest/api/content/(\d+)\z}] then delete_attachment(::Regexp.last_match(1))
    else [404, JSON.generate(message: "no route #{verb} #{uri.path}")]
    end
  end

  def ok(data) = [200, JSON.generate(data)]

  def page_json(id)
    page = @pages[id] or return [404, JSON.generate(message: "No content found with id #{id}")]
    ok(id: page.id, title: page.title, space: { key: page.space }, body: { storage: { value: page.body } },
       version: { number: page.version, by: { displayName: page.by }, when: page.at })
  end

  def find(query)
    page = @pages.values.find { |p| p.space == query["spaceKey"] && p.title == query["title"] }
    ok(results: page ? [{ id: page.id }] : [])
  end

  def update(id, payload)
    page = @pages.fetch(id)
    return [409, JSON.generate(message: "version mismatch")] unless payload.dig("version", "number") == page.version + 1

    page.version += 1
    page.by = "Exporter"
    page.at = "2026-03-03T09:00:00.000Z"
    page.body = payload.dig("body", "storage", "value")
    page.properties[:message] = payload.dig("version", "message")
    ok(id: id, version: { number: page.version })
  end

  def get_property(id, key)
    prop = @pages.fetch(id).properties[key]
    prop ? ok(key: key, value: prop[:value], version: { number: prop[:version] }) : [404, JSON.generate(message: "no property")]
  end

  def create_property(id, payload)
    @pages.fetch(id).properties[payload["key"]] = { value: payload["value"], version: 1 }
    ok(key: payload["key"])
  end

  def update_property(id, key, payload)
    @pages.fetch(id).properties[key] = { value: payload["value"], version: payload.dig("version", "number") }
    ok(key: key)
  end

  def list_attachments(id)
    ok(results: @pages.fetch(id).attachments.map { |name, a| { title: name, id: a[:id] } })
  end

  def upload(id, existing_id, headers, body)
    return [403, JSON.generate(message: "XSRF check failed")] unless headers["X-Atlassian-Token"] == "no-check"

    name = body[/filename="([^"]+)"/, 1]
    attachments = @pages.fetch(id).attachments
    attachments[name] = { id: existing_id || (@next_attachment += 1).to_s }
    @uploads << { page: id, filename: name, replaced: !existing_id.nil? }
    ok(results: [{ title: name }])
  end

  def delete_attachment(attachment_id)
    @pages.each_value { |page| page.attachments.delete_if { |_, a| a[:id] == attachment_id } }
    @deleted << attachment_id
    [204, ""]
  end

  def restrict(id, payload)
    return [403, JSON.generate(message: restriction_error)] if restriction_error

    @pages.fetch(id).restriction = payload
    ok(payload)
  end
end
