# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require "time"
require_relative "../../version"
require_relative "../../assets"
require_relative "../../helpers"
require_relative "client"
require_relative "credentials"
require_relative "page_url"
require_relative "storage"
require_relative "page_properties"

module Archsight
  module Export
    module Confluence
      # Publishes wiki pages to the Confluence pages they link to (`confluence:` in the frontmatter).
      #
      # A page is only written when Confluence still holds what Archsight wrote last time: the exporter leaves a
      # marker (a content property with the page version it created) and refuses to overwrite a page that has
      # no marker or a newer version, unless `force` is set. Every written version says in its message that it
      # was generated, and the page is locked for other editors where the server allows it.
      class Exporter
        PROPERTY = "archsight"

        # status: :exported, :would_export, :unchanged, :blocked, :skipped, :failed
        Result = Struct.new(:page, :status, :message, keyword_init: true)

        # @param database [Archsight::Database]
        # @param settings [Credentials::Settings, nil] token and draw.io support; default: Credentials.load
        # @param drawio [Boolean, nil] overrides the settings' draw.io flag
        # @param tags [Array<String>] only export pages that have at least one of these `page/tags` (case-insensitive)
        # @param client_factory [#call, nil] `(base_url, token) -> Client`, for tests
        def initialize(database:, resources_dir:, force: false, lock: true, dry_run: false, settings: nil, drawio: nil, tags: [], client_factory: nil)
          @database = database
          @resources_dir = resources_dir
          @force = force
          @lock = lock
          @dry_run = dry_run
          @settings = settings
          @drawio = drawio
          @tags = Array(tags).map { |t| t.to_s.strip.downcase }.reject(&:empty?)
          @client_factory = client_factory || ->(base, secret) { Client.new(base: base, token: secret) }
          @clients = {}
        end

        # @param names [Array<String>] pages to export; none means every page with a Confluence link
        # @return [Array<Result>]
        def run(names = [])
          select(names).map { |page, result| result || export(page) }
        end

        private

        # @return [Array<Array(Page|String, Result|nil)>]
        def select(names)
          all = @database.instances_by_kind("Page")
          return all.values.select { |p| link(p) && tagged?(p) }.sort_by(&:name).map { |p| [p, nil] } if names.empty?

          names.map do |name|
            page = all[name]
            if page.nil? then [name, Result.new(page: name, status: :failed, message: "no such page")]
            elsif link(page).nil? then [page, Result.new(page: name, status: :skipped, message: "no `confluence:` link in the frontmatter")]
            elsif !tagged?(page) then [page, Result.new(page: name, status: :skipped, message: "has none of the tags #{@tags.join(", ")}")]
            else [page, nil]
            end
          end
        end

        def tagged?(page)
          return true if @tags.empty?

          page.annotations["page/tags"].to_s.split(",").map { |t| t.strip.downcase }.intersect?(@tags)
        end

        def link(page)
          value = page.annotations["page/confluence"].to_s.strip
          value.empty? ? nil : value
        end

        def export(page)
          url = PageUrl.parse(link(page))
          client = client_for(url.base)
          id = url.page_id || client.find_page_id(url.space, url.title)
          return failed(page, "no page #{url.title.inspect} in space #{url.space}") unless id

          content = client.content(id)
          property = client.property(id, PROPERTY)
          blocked = manipulation(content, property&.value)
          return Result.new(page: page.name, status: :blocked, message: blocked) if blocked && !@force

          converted = convert(page, url, id)
          return failed(page, "cannot be exported: #{converted.problems.join("; ")}") if converted.problems.any?

          write(page, client, content, property, converted, blocked, id)
        rescue ArgumentError, Archsight::Export::Error => e
          failed(page, e.message)
        end

        # Why the page must not be overwritten, nil if Confluence holds what Archsight wrote last
        def manipulation(content, marker)
          return "was not exported by Archsight before (use --force to replace its content)" if marker.nil?

          current = content.dig("version", "number")
          return nil if current == marker["version"]

          who = content.dig("version", "by", "displayName") || "someone"
          "modified in Confluence by #{who} at #{content.dig("version", "when")} (version #{current}, last exported #{marker["version"]}); " \
            "use --force to overwrite"
        end

        def convert(page, url, id)
          storage = Storage.new(page_name: page.name, source: relative_source(page),
                                base_dir: Assets.base_dir_for(page, resources_dir: @resources_dir).to_s,
                                resources_dir: @resources_dir, wiki: Helpers::WikiLinks.new(@database), page_id: id, base: url.base,
                                drawio: drawio?, diagram_links: DiagramLinks.new(@database), database: @database)
          storage.convert(body_of(page), toc: page.annotations["page/toc"] == "yes", header: PageProperties.xml(page))
        end

        # The Confluence title is shown above the body, so a leading "# Title" that repeats it is dropped
        def body_of(page)
          body = page.annotations["page/content"].to_s
          first, rest = body.lstrip.split("\n", 2)
          heading = first.to_s[/\A#\s+(.+?)\s*#*\s*\z/, 1]
          heading && [page.title, page.name].any? { |t| t.to_s.casecmp?(heading) } ? rest.to_s : body
        end

        def relative_source(page)
          Pathname.new(Assets.real(page.path_ref.path)).relative_path_from(Pathname.new(Assets.real(@resources_dir))).to_s
        rescue ArgumentError, SystemCallError
          File.basename(page.path_ref.path.to_s)
        end

        def write(page, client, content, property, converted, blocked, id)
          marker = property&.value
          current = content.dig("version", "number")
          body_hash = Digest::SHA256.hexdigest(converted.body)
          files = converted.attachments.transform_values(&:sha)
          return Result.new(page: page.name, status: :unchanged, message: "version #{current}") if !blocked && marker["bodyHash"] == body_hash && marker["attachments"] == files
          return would_export(page, current, blocked) if @dry_run

          upload(client, id, converted.attachments, marker&.fetch("attachments", nil) || {})
          updated = client.update_page(id, title: content["title"], space: content.dig("space", "key"), body: converted.body,
                                           version: current + 1, message: message(page, blocked, marker, current))
          version = updated.dig("version", "number")
          state = { "version" => version, "bodyHash" => body_hash, "attachments" => files, "page" => page.name,
                    "exportedAt" => Time.now.utc.iso8601, "archsight" => Archsight::VERSION }
          client.save_property(id, PROPERTY, state, property)
          remove_stale_attachments(client, id, marker, files)
          Result.new(page: page.name, status: :exported, message: "version #{version}#{lock(client, id)}")
        end

        def would_export(page, current, blocked)
          Result.new(page: page.name, status: :would_export,
                     message: "would write version #{current + 1}#{" (overwriting: #{blocked})" if blocked}")
        end

        def upload(client, id, attachments, known)
          remote = client.attachments(id)
          attachments.each_value do |attachment|
            next if known[attachment.filename] == attachment.sha && remote.key?(attachment.filename)

            client.upload_attachment(id, filename: attachment.filename, data: attachment.data, content_type: attachment.content_type,
                                         existing_id: remote[attachment.filename], comment: "Generated by Archsight")
          end
        end

        # Attachments an earlier export uploaded that the page does not use any more (a diagram that was removed,
        # or shown differently now). Only files recorded in the marker are touched, never ones somebody else added.
        def remove_stale_attachments(client, id, marker, current_files)
          stale = (marker&.fetch("attachments", nil) || {}).keys - current_files.keys
          return if stale.empty?

          client.attachments(id).slice(*stale).each_value { |attachment_id| client.delete_attachment(attachment_id) }
        end

        def message(page, blocked, marker, current)
          note = if blocked && marker then "; overwrote the changes of versions #{marker["version"] + 1}..#{current}"
                 elsif blocked then "; replaced the content that was there"
                 end
          "Generated by Archsight #{Archsight::VERSION} from #{relative_source(page)}, do not edit in Confluence#{note}"
        end

        # Best effort: only the exporting user may edit the page. Returns text for the report.
        def lock(client, id)
          return "" unless @lock

          client.restrict_update_to(id, @user.fetch("username"))
          ", locked for other editors"
        rescue Archsight::Export::Error => e
          ", NOT locked (#{e.message})"
        end

        def client_for(base)
          @clients[base] ||= begin
            client = @client_factory.call(base, settings.token)
            @user = client.current_user
            client
          end
        end

        def settings
          @settings ||= Credentials.load
        end

        def drawio?
          @drawio.nil? ? settings.drawio : @drawio
        end

        def failed(page, message)
          Result.new(page: page.respond_to?(:name) ? page.name : page, status: :failed, message: message)
        end
      end
    end
  end
end
