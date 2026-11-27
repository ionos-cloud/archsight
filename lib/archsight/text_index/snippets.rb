# frozen_string_literal: true

module Archsight
  class TextIndex
    # Excerpts of a hit around the words its query searched for: the annotations where most of the searched words occur,
    # each cut to the window that holds most of them, as plain text (markdown taken off) with the ranges to mark.
    module Snippets
      ELLIPSIS = "…"
      # titles are shown as the title of a hit, not as an excerpt
      TITLE_KEYS = %w[page/title architecture/title].freeze

      class << self
        # [{key:, title:, text:, marks: [[from, to]]}] of `instance`, best first, at most `limit`
        def for(instance, matcher, limit: 2, width: 180)
          return [] if matcher.empty?

          candidates = instance.annotations.filter_map do |key, value|
            next if !value.is_a?(String) || TITLE_KEYS.include?(key)

            annotation = instance.class.annotation_matching(key)
            text = annotation&.markdown? ? plain_markdown(value) : squeeze(value)
            hits = matcher.ranges(text, key)
            # a regex may look for the markdown itself (`text =~ /\[\[Page/`): then the excerpt is of the source
            hits = matcher.ranges(text = squeeze(value), key) if hits.empty? && annotation&.markdown?
            [key, annotation, text, hits] unless hits.empty?
          end
          best = candidates.sort_by { |key, _, _, hits| [-distinct(hits), -hits.size, key == "architecture/description" ? 0 : 1, key] }
          best.first(limit).map do |key, annotation, text, hits|
            title = annotation && !annotation.pattern? ? annotation.title : key
            excerpt(text, hits, width, matcher).merge(key: key, title: title)
          end
        end

        # The title shown for a hit (page or architecture title, else the name) and what to mark in it
        def title(instance, matcher)
          text = instance.annotations["page/title"] || instance.annotations["architecture/title"] || instance.name.to_s
          { title: text, title_marks: matcher.empty? ? [] : matcher.marks(text) }
        end

        # Markdown as running text: no fences, headings, emphasis, link targets, tags or macros
        def plain_markdown(text)
          squeeze(
            text.sub(/\A\s*#\s+[^\n]*\n/, "") # a leading title heading repeats the title of the hit
                .gsub(/^\s*(```|~~~).*$/, " ")
                .gsub(/^\s{0,3}\#{1,6}\s+/, "")
                .gsub(/!\[([^\]]*)\]\([^)]*\)/, '\1')
                .gsub(/\[([^\]]+)\]\([^)]*\)/, '\1')
                .gsub(/\[\[(?:[^\]|]*\|)?([^\]]+)\]\]/, '\1')
                .gsub(/<[^>]+>/, " ")
                .gsub(/\{[a-z]+(?::[^}]*)?\}/, " ")
                .gsub(/(\*\*|__|`)/, "")
                .gsub(/^\s*[-*+>|]\s+/, "")
                .tr("|", " ")
          )
        end

        def squeeze(text)
          text.gsub(/\s+/, " ").strip
        end

        private

        def distinct(hits)
          hits.map(&:last).uniq.size
        end

        # The window of about `width` characters with the most different searched words, at word boundaries
        def excerpt(text, hits, width, matcher)
          from, to = best_window(text, hits, width)
          inside = hits.select { |start, stop, _| start >= from && stop <= to }
          lead = from.positive? ? ELLIPSIS : ""
          trail = to < text.length ? ELLIPSIS : ""
          marks = matcher.merge(inside.map { |start, stop, _| [start - from + lead.length, stop - from + lead.length] })
          { text: "#{lead}#{text[from...to]}#{trail}", marks: marks }
        end

        def best_window(text, hits, width)
          return [0, text.length] if text.length <= width

          windows = hits.map do |start, _, _|
            from = (start - (width / 4)).clamp(0, text.length - width)
            to = from + width
            inside = hits.select { |s, e, _| s >= from && e <= to }
            [from, to, distinct(inside), inside.size]
          end
          from, to, = windows.max_by { |f, _, kinds, count| [kinds, count, -f] }
          [snap_start(text, from), snap_end(text, to)]
        end

        # a window starts after a space (unless the text starts there) and ends before one
        def snap_start(text, from)
          return 0 if from.zero?

          space = text.index(" ", from)
          space && space - from < 20 ? space + 1 : from
        end

        def snap_end(text, to)
          return text.length if to >= text.length

          space = text.rindex(" ", to)
          space && to - space < 20 ? space : to
        end
      end
    end
  end
end
