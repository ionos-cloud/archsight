# frozen_string_literal: true

require_relative "typst"
require_relative "../assets"

module Archsight
  module Pdf
    # The look of an exported document: what a Config resource of type pdf says, with a neutral built-in look for
    # everything it leaves out (or for no template at all). Every value is checked here, so a template loaded
    # from a file that was never linted cannot put anything but a colour, a font name or a length into the
    # Typst source.
    class Theme
      DEFAULT_NAME = "default"
      TYPE = "pdf" # the `config/type` of the Configs that describe the look
      COLORS = {
        primary: "#1f3a5f", accent: "#2f7fd1", text: "#1c1c1c", muted: "#6b7280",
        ok: "#1f9d55", warn: "#d98e04", danger: "#c0392b"
      }.freeze
      FONTS = {
        body: ["Liberation Sans", "DejaVu Sans", "Helvetica", "Arial"],
        heading: ["Liberation Sans", "DejaVu Sans", "Helvetica", "Arial"],
        mono: ["DejaVu Sans Mono", "Liberation Mono", "Menlo", "Courier New"]
      }.freeze
      PAPERS = %w[a4 a5 us-letter].freeze
      LANGS = %w[en de].freeze
      HEADER_PARTS = %w[id version date owner].freeze
      DEFAULT_MARGIN = "16mm"
      LOGO_TYPES = %w[.svg .png].freeze

      attr_reader :name, :colors, :fonts, :footer_text, :classification, :header_meta, :lang, :paper, :margin,
                  :logo, :logo_light, :font_dir, :break_before, :keep_space

      # @param template [Archsight::Resources::Config, nil]
      # @param resources_dir [String] logos and fonts are looked up below it
      def initialize(template = nil, resources_dir: Archsight.resources_dir)
        @name = template&.name
        ann = template ? template.annotations : {}
        @colors = COLORS.to_h { |key, default| [key, color(ann["pdf/color-#{key}"], default)] }
        @fonts = FONTS.to_h { |key, default| [key, font_list(ann["pdf/font-#{key}"], default)] }
        @footer_text = blank_to_nil(ann["pdf/footer-text"])
        @classification = blank_to_nil(ann["pdf/classification"])
        @header_meta = header_parts(ann["pdf/header-meta"])
        @lang = LANGS.include?(ann["pdf/lang"]) ? ann["pdf/lang"] : "en"
        @paper = PAPERS.include?(ann["pdf/paper"]) ? ann["pdf/paper"] : "a4"
        @margin = ann["pdf/margin"].to_s.match?(Resources::Config::LENGTH) ? ann["pdf/margin"] : DEFAULT_MARGIN
        @break_before = heading_levels(ann["pdf/break-before"])
        @keep_space = space_shares(ann["pdf/keep-space"], @break_before)
        @logo = logo_file(ann["pdf/logo"], resources_dir)
        @logo_light = logo_file(ann["pdf/logo-light"], resources_dir) || @logo
        @font_dir = font_directory(ann["pdf/font-dir"], resources_dir)
      end

      # The Config a document asks for (`pdf:template:<name>`), else the one named `default`, else the built-in look. Only
      # Configs of type pdf count.
      # @param requested [String, nil] name as written in the tag, with or without the `Config:` and `PDF:` prefixes
      def self.for(database, requested = nil)
        wanted = (requested || DEFAULT_NAME).to_s.strip
        configs = database.instances_by_kind("Config").values.select { |c| c.annotations["config/type"].to_s.casecmp?(TYPE) }
        new(configs.find { |config| matches?(config.name, wanted) })
      end

      # `brand`, `PDF:brand` and `Config:PDF:brand` all name the same Config
      def self.matches?(name, wanted)
        short(name).casecmp?(short(wanted))
      end

      def self.short(name)
        name.to_s.strip.sub(/\AConfig:/i, "").sub(/\APDF:/i, "")
      end

      # Typst source defining `theme`. `logo` and `logo_light` are the file names the logos were staged under.
      def to_typst(logo: nil, logo_light: nil)
        fields = colors.map { |key, hex| "#{key}: #{Typst.color(hex)}" }
        fields += fonts.map { |key, list| "font-#{key}: (#{list.map { |f| Typst.lit(f) }.join(", ")},)" }
        fields += [
          "logo: #{logo ? Typst.lit(logo) : "none"}", "logo-light: #{logo_light ? Typst.lit(logo_light) : "none"}",
          "footer-text: #{footer_text ? Typst.lit(footer_text) : "none"}",
          "header-meta: (#{header_meta.map { |p| Typst.lit(p) }.join(", ")},)",
          "lang: #{Typst.lit(lang)}", "paper: #{Typst.lit(paper)}", "margin: #{margin}",
          "break-before: #{array(break_before)}", "keep-space: #{array(keep_space.map { |level, share| "(#{level}, #{share})" })}"
        ]
        "#let theme = (#{fields.join(", ")})\n"
      end

      private

      # A Typst array of ready-made items; `()` is the empty one, `(x,)` has one item
      def array(items)
        items.empty? ? "()" : "(#{items.join(", ")},)"
      end

      def color(value, default)
        value.to_s.strip.match?(Resources::Config::COLOR) ? value.to_s.strip : default
      end

      def font_list(value, default)
        name = value.to_s.strip
        name.match?(Resources::Config::FONT_NAME) ? [name, *default] : default
      end

      def header_parts(value)
        return HEADER_PARTS if value.to_s.strip.empty?

        parts = value.to_s.split(",").map(&:strip) & HEADER_PARTS
        parts.empty? ? HEADER_PARTS : parts
      end

      # @return [Array<Integer>] the heading levels that start a new page
      def heading_levels(value)
        value.to_s.split(",").map(&:strip).grep(/\A[1-6]\z/).map(&:to_i).uniq.sort
      end

      # @return [Array<Array(Integer, Integer)>] [level, percent of the page that must be left]; a level that always
      #   breaks needs no share
      def space_shares(value, always)
        value.to_s.split(",").filter_map do |part|
          match = part.strip.match(Resources::Config::KEEP_SPACE)
          level = match && match[1].to_i
          share = match && match[2].to_i
          [level, share] if level && share.between?(1, 100) && !always.include?(level)
        end.uniq(&:first)
      end

      def blank_to_nil(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      # @return [String, nil] absolute path of a logo inside the resources directory
      def logo_file(path, resources_dir)
        return nil if path.to_s.strip.empty?

        file = Assets.file_for(path.to_s, resources_dir: resources_dir)
        file if file && LOGO_TYPES.include?(File.extname(file).downcase)
      end

      def font_directory(path, resources_dir)
        normalized = Assets.normalize(path.to_s)
        return nil unless normalized

        root = File.realpath(resources_dir)
        dir = File.realpath(File.join(root, normalized))
        dir if dir.start_with?(root + File::SEPARATOR) && File.directory?(dir)
      rescue SystemCallError
        nil
      end
    end
  end
end
