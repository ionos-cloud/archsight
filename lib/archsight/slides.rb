# frozen_string_literal: true

require_relative "assets"
require_relative "user_config"

module Archsight
  # The finished slide deck a page shows (`slides:` in its frontmatter): a PDF, or one self-contained HTML page made by
  # any slide tool. Archsight does not render slides; it serves the file and embeds it next to the page's summary.
  #
  # An HTML deck is somebody else's script, so it is only ever served inside a sandbox: a Content-Security-Policy with
  # `sandbox allow-scripts` (no `allow-same-origin`) gives it an opaque origin, which cannot reach the API or the
  # storage of Archsight, also when the file is opened on its own. Scripts may come from the hosts of the setting
  # `slides.script_hosts` (`ARCHSIGHT_SLIDES_SCRIPT_HOSTS`, space or comma separated), by default the common CDNs.
  module Slides
    DEFAULT_SCRIPT_HOSTS = %w[https://unpkg.com https://cdn.jsdelivr.net https://cdnjs.cloudflare.com].freeze
    HOST = %r{\Ahttps://[A-Za-z0-9.-]+(:\d+)?\z}

    module_function

    # @return [Array<String>] the hosts an HTML deck may load scripts, styles and fonts from (`https://host` only)
    def script_hosts
      setting = UserConfig.setting("slides", "script_hosts")
      return DEFAULT_SCRIPT_HOSTS unless setting

      setting.to_s.split(/[\s,]+/).grep(HOST)
    end

    # @return [String] the Content-Security-Policy of an HTML deck
    def csp(hosts = script_hosts)
      list = hosts.join(" ")
      [
        "sandbox allow-scripts allow-popups",
        "default-src 'none'",
        "script-src 'unsafe-inline' 'unsafe-eval' blob: data: #{list}".strip,
        "style-src 'unsafe-inline' blob: data: #{list}".strip,
        "font-src data: blob: #{list}".strip,
        "img-src data: blob:",
        "media-src data: blob:",
        "connect-src blob: data:"
      ].join("; ")
    end

    # The deck of a page for the API
    # @return [Hash, nil] `{url:, filename:, type:, cover_url:}`, nil if the page has none or the reference is not servable
    def for_page(page, resources_dir: Archsight.resources_dir)
      reference = page.annotations["page/slides"].to_s.strip
      return nil if reference.empty?

      base = Assets.base_dir_for(page, resources_dir: resources_dir)
      path = base && Assets.resolve_reference(reference, base)
      return nil unless path && Assets.deck_problem(path, resources_dir: resources_dir).nil?

      { url: Assets.deck_url_for(path), filename: File.basename(path), type: Assets.html_deck?(path) ? "html" : "pdf",
        cover_url: cover_url(page, base, resources_dir) }
    end

    def cover_url(page, base, resources_dir)
      reference = page.annotations["page/cover"].to_s.strip
      path = !reference.empty? && Assets.resolve_reference(reference, base)
      path && Assets.problem(path, resources_dir: resources_dir).nil? ? Assets.url_for(path) : nil
    end

    # Problems of the `page/slides` and `page/cover` references of a page, for the linter
    # @return [Array<String>]
    def audit(page, resources_dir:)
      base = Assets.base_dir_for(page, resources_dir: resources_dir)
      return [] unless base

      [["page/slides", ->(path) { Assets.deck_problem(path, resources_dir: resources_dir) }, Assets::DECK_TYPES],
       ["page/cover", ->(path) { Assets.problem(path, resources_dir: resources_dir) }, Assets::TYPES]].filter_map do |key, check, types|
        reference = page.annotations[key].to_s.strip
        next if reference.empty?

        problem(key, reference, base, check, types)
      end
    end

    def problem(key, reference, base, check, types)
      path = Assets.resolve_reference(reference, base)
      return "#{key} #{reference.inspect} is not a path inside the resources directory" unless path

      case check.call(path)
      when :type then "#{key} #{reference.inspect} must be #{types.keys.join(", ")}"
      when :missing then "#{key} #{reference.inspect} does not exist (#{path})"
      end
    end
  end
end
