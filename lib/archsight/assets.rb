# frozen_string_literal: true

require "erb"
require "pathname"

module Archsight
  # Assets are the files that markdown can embed: images and draw.io diagrams. "assets" is the name of
  # the one door to them, the API (`/api/v1/assets/<path>`); on disk they are ordinary files of the
  # resources directory, wherever they belong, typically next to the markdown that uses them:
  #
  #   pages/handbook/home.md   ![](../img/a.png)         ->  pages/img/a.png
  #   pages/handbook/home.md   ![](../../fop/bar.drawio) ->  fop/bar.drawio
  #
  # A reference is resolved against the directory of the markdown file (relative to the resources
  # directory) and normalized. The boundary is the resources directory and the list of served types:
  # everything that could leave the directory is rejected, never clamped (`..` above the root, absolute
  # paths, backslashes, control characters, dotfiles, symlinks that point out), and every file type that
  # is not on the allowlist is not served, so resource definitions (YAML, markdown) and sources can never
  # be read through the API.
  module Assets
    URL_PREFIX = "/api/v1/assets/"
    MAX_BYTES = 25 * 1024 * 1024
    MAX_PATH = 1024

    # The only types that are served, with the Content-Type they are served as (never guessed)
    TYPES = {
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif" => "image/gif",
      ".webp" => "image/webp",
      ".avif" => "image/avif",
      ".svg" => "image/svg+xml",
      ".drawio" => "application/xml"
    }.freeze
    DRAWIO = ".drawio"

    SCHEME = /\A[A-Za-z][A-Za-z0-9+.-]*:/
    UNSAFE_CHARS = /[\x00-\x1f\x7f\\]/

    module_function

    # A path relative to the resources directory without `.`/`..`/empty segments, or nil if it is not safe: it
    # climbs above the root, is absolute, has a drive letter, backslashes or control characters, a segment that starts
    # with a dot, or is empty. No I/O, no decoding.
    # @param path [String] e.g. "pages/handbook/../img/a.png"
    # @return [String, nil] e.g. "pages/img/a.png"
    def normalize(path)
      return nil unless path.is_a?(String) && path.valid_encoding? && path.bytesize <= MAX_PATH
      return nil if path.match?(UNSAFE_CHARS) || path.start_with?("/") || path.match?(/\A[A-Za-z]:/)

      segments = [] #: Array[String]
      path.split("/").each do |segment|
        case segment
        when "", "." then next
        when ".."
          return nil if segments.empty? # would leave the resources directory

          segments.pop
        else
          return nil if segment.start_with?(".")

          segments << segment
        end
      end
      segments.empty? ? nil : segments.join("/")
    end

    # Whether a markdown reference points somewhere else than a file of the resources (a URL with a
    # scheme, a protocol-relative or server-absolute URL, a fragment or query only). Those are left alone.
    def external?(reference)
      ref = reference.to_s.strip
      ref.empty? || ref.start_with?("/", "#", "?") || ref.match?(SCHEME)
    end

    # The normalized asset path (relative to the resources directory) a markdown reference stands for.
    # @param reference [String] as written in the markdown (URL syntax: may be percent-encoded, may have ?query/#fragment)
    # @param base_dir [String] directory of the markdown file relative to the resources directory ("" for the root)
    # @return [String, nil] nil if the reference is unsafe or escapes the resources directory
    def resolve_reference(reference, base_dir)
      path = decode(reference.to_s.strip.sub(/[?#].*\z/m, ""))
      return nil if path.nil? || path.empty?

      base = base_dir.to_s
      normalize(base.empty? ? path : "#{base}/#{path}")
    end

    # Percent-decoding, once (references are URLs). Invalid UTF-8 or an invalid escape -> nil.
    def decode(text)
      decoded = text.gsub(/%(\h\h)/) { ::Regexp.last_match(1).hex.chr }.dup.force_encoding(Encoding::UTF_8)
      decoded.valid_encoding? ? decoded : nil
    end

    # Why a normalized path is not served: :type (not on the allowlist) or :missing (also for a path
    # that leads out of the resources directory through a symlink); nil if it is served.
    def problem(path, resources_dir:)
      return :type unless TYPES.key?(File.extname(path).downcase)

      file_for(path, resources_dir: resources_dir) ? nil : :missing
    end

    # The real file of an asset, only if it is a regular file of an allowed type inside the real resources directory.
    # @param path [String] relative to the resources directory, as received (it is normalized here, so callers cannot forget to)
    # @return [String, nil] absolute path, nil if there is no such servable asset
    def file_for(path, resources_dir:)
      normalized = normalize(path)
      return nil unless normalized && TYPES.key?(File.extname(normalized).downcase)

      root = File.realpath(resources_dir)
      real = File.realpath(File.join(root, normalized))
      real.start_with?(root + File::SEPARATOR) && File.file?(real) ? real : nil
    rescue SystemCallError
      nil
    end

    def content_type(path)
      TYPES.fetch(File.extname(path).downcase)
    end

    def drawio?(path)
      File.extname(path).casecmp?(DRAWIO)
    end

    # URL under which the API serves a normalized asset path
    def url_for(path)
      URL_PREFIX + path.split("/").map { |segment| ERB::Util.url_encode(segment) }.join("/")
    end

    # Directory of the file a resource (page, YAML resource) was loaded from, relative to the resources
    # directory ("" for the root), nil if it is not below it
    def base_dir_for(resource, resources_dir:)
      file = resource.path_ref&.path
      return nil unless file

      relative = Pathname.new(real(file)).relative_path_from(Pathname.new(real(resources_dir))).to_s
      return nil if relative == ".." || relative.start_with?("../")

      dir = File.dirname(relative)
      dir == "." ? "" : dir
    rescue ArgumentError, SystemCallError
      nil
    end

    # The real path of a file, also for one that does not exist (yet): the nearest existing parent is resolved
    # so that /var and /private/var, or a symlinked resources directory, compare equal
    def real(path)
      path = File.expand_path(path)
      rest = [] #: Array[String]
      until File.exist?(path) || path == File.dirname(path)
        rest.unshift(File.basename(path))
        path = File.dirname(path)
      end
      File.join(File.realpath(path), *rest)
    end
  end
end
