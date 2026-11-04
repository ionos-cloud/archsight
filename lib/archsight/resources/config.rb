# frozen_string_literal: true

# Config holds settings of a feature of the tool, kept with the model so they are shared and versioned like it
class Archsight::Resources::Config < Archsight::Resources::Base
  include_annotations :architecture

  description <<~MD
    Holds the settings of a feature of the tool, such as the look of the PDF export.

    ## Definition

    A Config is a tool-specific resource type. It carries no architecture, only settings, so that everything that
    should look or behave the same is written once and shared through the resources repository instead of being
    repeated in every page. It is not the per-user configuration file (tokens, URLs of other systems): that stays in
    `~/.config/archsight/archsight.yaml`.

    ## Type

    `config/type` says which feature the settings are for; the feature looks up its own Configs by type, so every
    feature can have a Config named `default`. The settings of a feature use the annotations of its own prefix.

    | `config/type` | Settings | Used by |
    |---------------|----------|---------|
    | `pdf` | `pdf/*`: colours, fonts, logo, header and footer | [PDF export](/doc/pdf-export) |

    A document picks a different Config of the type with the tag `pdf:template:<name>`; without a tag the one named
    `default` is used, and without any the export has a neutral built-in look.

    ## PDF settings

    - **Colours** (`pdf/color-*`) are hex values (`#0b3d91`). `primary` is used for headings, the cover band and
      table headers, `accent` for rules and links.
    - **Fonts** (`pdf/font-*`) are family names. Fonts that are not installed fall back to the built-in ones; put
      font files in a directory of the resources and name it in `pdf/font-dir` to ship them with the model.
    - **Logos** (`pdf/logo`, `pdf/logo-light`) are image files (svg, png) of the resources directory, given
      relative to it. `logo` goes on white (page header), `logo-light` on the coloured cover band.
    - **Texts** (`pdf/footer-text`, `pdf/classification`) appear on every page.
  MD

  icon "settings"
  layer "other"

  TYPE_FORMAT = /\A[a-z][a-z0-9-]*\z/

  annotation "config/type",
             description: "The feature these settings are for (pdf). The feature looks up its Configs by this type",
             title: "Type",
             filter: :word,
             summary: true,
             validator: ->(value) { Archsight::Resources::Config.pattern_error(value, TYPE_FORMAT, "a lowercase word such as pdf") }

  COLOR = /\A#(\h{3}|\h{6})\z/
  FONT_NAME = /\A[\p{L}\p{N} ._+-]{1,80}\z/
  LENGTH = /\A\d+(\.\d+)?(mm|cm|pt|in)\z/

  # Colour annotations: key suffix, title, role
  COLORS = {
    "primary" => ["Primary colour", "headings, cover band, table headers"],
    "accent" => ["Accent colour", "rules and links"],
    "text" => ["Text colour", "body text"],
    "muted" => ["Muted colour", "secondary text, header and footer"],
    "ok" => ["Positive colour", "good status"],
    "warn" => ["Warning colour", "warning status"],
    "danger" => ["Danger colour", "bad status and the classification marking"]
  }.freeze

  COLORS.each do |key, (title, role)|
    annotation "pdf/color-#{key}",
               description: "#{title} as hex value (#rrggbb), used for #{role}",
               title: title,
               validator: ->(value) { Archsight::Resources::Config.pattern_error(value, COLOR, "a hex colour such as #0b3d91") },
               sidebar: false
  end

  %w[body heading mono].each do |role|
    annotation "pdf/font-#{role}",
               description: "Font family of the #{role} text",
               title: "#{role.capitalize} font",
               validator: ->(value) { Archsight::Resources::Config.pattern_error(value, FONT_NAME, "a font family name") },
               sidebar: false
  end

  annotation "pdf/font-dir",
             description: "Directory with font files (ttf, otf), relative to the resources directory",
             title: "Font directory",
             sidebar: false

  annotation "pdf/logo",
             description: "Logo for the page header (svg or png), path relative to the resources directory",
             title: "Logo",
             validator: ->(value) { Archsight::Resources::Config.logo_error(value) },
             sidebar: false
  annotation "pdf/logo-light",
             description: "Logo for the coloured cover band (svg or png), path relative to the resources directory",
             title: "Logo (light)",
             validator: ->(value) { Archsight::Resources::Config.logo_error(value) },
             sidebar: false

  annotation "pdf/footer-text",
             description: "Text in the footer of every page (centre)",
             title: "Footer text",
             sidebar: false
  annotation "pdf/classification",
             description: "Marking shown in the footer of every page, e.g. Internal. A document can override it with " \
                          "the page property Classification",
             title: "Classification",
             sidebar: false
  annotation "pdf/header-meta",
             description: "Comma-separated parts of the header line: id, version, date, owner (default: all)",
             title: "Header line",
             sidebar: false,
             validator: ->(value) { Archsight::Resources::Config.header_meta_error(value) }
  annotation "pdf/lang",
             description: "Language of the fixed texts (page, contents, ...)",
             title: "Language",
             enum: %w[en de],
             sidebar: false
  annotation "pdf/paper",
             description: "Paper size",
             title: "Paper",
             enum: %w[a4 a5 us-letter],
             sidebar: false
  annotation "pdf/margin",
             description: "Horizontal page margin as length (e.g. 16mm)",
             title: "Margin",
             validator: ->(value) { Archsight::Resources::Config.pattern_error(value, LENGTH, "a length such as 16mm") },
             sidebar: false

  annotation "pdf/break-before",
             description: "Heading levels that always start a new page, comma-separated (e.g. 1, or 1,2). The first heading " \
                          "of a document stays on the first page. A page tag pdf:no-breaks switches the breaks off",
             title: "New page before",
             sidebar: false,
             validator: ->(value) { Archsight::Resources::Config.break_before_error(value) }
  annotation "pdf/keep-space",
             description: "Heading levels that start a new page when less than the given share of the page is left, as " \
                          "level:share, comma-separated (e.g. 2:30% or 2:30%,3:20%)",
             title: "Space a heading needs",
             sidebar: false,
             validator: ->(value) { Archsight::Resources::Config.keep_space_error(value) }

  HEADER_PARTS = %w[id version date owner].freeze
  HEADING_LEVELS = (1..6).to_a.freeze
  KEEP_SPACE = /\A([1-6]):(\d{1,3})%?\z/

  # Validator helpers: nil if the value is fine, else the message
  def self.pattern_error(value, pattern, expected)
    value.to_s.match?(pattern) ? nil : "expected #{expected}"
  end

  def self.logo_error(value)
    ext = File.extname(value.to_s).downcase
    return nil if %w[.svg .png].include?(ext) && Archsight::Assets.normalize(value.to_s)

    "expected a path of an svg or png file relative to the resources directory"
  end

  def self.header_meta_error(value)
    unknown = value.to_s.split(",").map(&:strip) - HEADER_PARTS
    unknown.empty? ? nil : "unknown part #{unknown.join(", ")}; use #{HEADER_PARTS.join(", ")}"
  end

  def self.break_before_error(value)
    levels = value.to_s.split(",").map(&:strip)
    bad = levels.grep_v(/\A[1-6]\z/)
    bad.empty? ? nil : "expected heading levels 1 to 6 such as 1,2, not #{bad.join(", ")}"
  end

  def self.keep_space_error(value)
    bad = value.to_s.split(",").map(&:strip).reject { |part| (m = part.match(KEEP_SPACE)) && m[2].to_i.between?(1, 100) }
    bad.empty? ? nil : "expected level:share such as 2:30%, not #{bad.join(", ")}"
  end
end
