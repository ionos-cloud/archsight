# frozen_string_literal: true

module Archsight
  module Diagram
    # A string that may hold markdown-lite markers (see
    # `TextMetrics.markdown_runs`). The lexer decides once, per string
    # literal, whether any marker could start in it (`detect`), so measuring
    # and rendering a plain label -- most of them, measured several times
    # each -- never looks for markers again: a plain `String` is a single
    # plain run. Anything built from a label has to carry the flag along
    # (`like`), or its markers render as literal text.
    class MarkdownText < String
      # Every marker (`**`, `__`, `*`, `[text](url)`) opens with one of these.
      MARKER_START = /[*_\[]/

      # `text` as a `MarkdownText` if a marker could start in it, else as is.
      def self.detect(text) = text.match?(MARKER_START) ? new(text) : text

      # `text`, flagged the way `source` is -- for a string built from a label.
      def self.like(source, text) = source.is_a?(self) ? new(text) : text
    end
  end
end
