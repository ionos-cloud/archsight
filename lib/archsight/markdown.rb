# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

module Archsight
  # The one way markdown is parsed, for the web, the export, the linter and the analysis output alike. GFM, but a
  # single newline inside a paragraph is a space, as in CommonMark and GitHub's rendering of `.md` files (the GFM
  # parser of kramdown would make it a `<br />`, as GitHub does in comments). A line break is two trailing spaces,
  # a trailing backslash or `<br>`.
  module Markdown
    OPTIONS = { input: "GFM", hard_wrap: false }.freeze

    # Raw HTML whose text is kept as it is
    VERBATIM = %w[pre code script style textarea].freeze

    # Fenced code and inline code, which are left as written
    CODE = /(^[ \t]*(?:`{3,}|~{3,}).*?^[ \t]*(?:`{3,}|~{3,})[ \t]*$|`+[^`\n].*?`+)/m
    WIKI_LINK_PIPE = /\[\[[^\]\n]*\]\]/

    def self.document(text, **)
      Kramdown::Document.new(protect_wiki_link_pipes(text.to_s), **OPTIONS, **)
    end

    # Kramdown reads every line with a `|` as a table row, which would cut `[[Target|label]]` in two (a list item
    # "Related: [[A/B|b]], [[C/D|d]]" became one table row). An escaped pipe is a plain `|` again in the HTML,
    # which is what WikiLinks expects; code is untouched, it would show the backslash.
    def self.protect_wiki_link_pipes(text)
      return text unless text.include?("[[") && text.include?("|")

      text.split(CODE).each_with_index.map do |part, index|
        index.odd? ? part : part.gsub(WIKI_LINK_PIPE) { |link| link.gsub(/(?<!\\)\|/, "\\\\|") }
      end.join
    end
    private_class_method :protect_wiki_link_pipes

    # The document without the newlines of the source in its text, for a target that keeps a newline instead of
    # reading it as a space (Confluence): a soft line break becomes a space, the newline after a line break goes.
    # Inline code over two lines is one line (as in CommonMark). Paragraphs, breaks and code blocks are unchanged.
    def self.unwrapped(text, **)
      document(text, **).tap { |doc| unwrap(doc.root) }
    end

    def self.unwrap(element)
      element.children.each_with_index do |child, index|
        if child.type == :text
          previous = index.positive? ? element.children[index - 1] : nil
          joined = child.value.gsub(/[ \t]*\r?\n[ \t]*/, " ")
          child.value = line_break?(previous) ? joined.lstrip : joined
        elsif child.type == :codespan
          child.value = child.value.gsub(/\r?\n/, " ")
        elsif !(child.type == :html_element && VERBATIM.include?(child.value))
          unwrap(child)
        end
      end
    end
    private_class_method :unwrap

    def self.line_break?(element)
      element && (element.type == :br || (element.type == :html_element && element.value == "br"))
    end
    private_class_method :line_break?
  end
end
