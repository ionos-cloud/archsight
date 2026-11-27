# frozen_string_literal: true

module Archsight
  class TextIndex
    # Finds where the text conditions of a query occur in a text, to show hits in context. A full-text condition is
    # looked for as the stems the index made of its words ("failovers" -> failov, matching failover, failovers, ...),
    # at the start of a word and ignoring case and accents; a regex condition (`text =~ /x/`, `text(keys) =~ "x"`) as
    # its regular expression, only in its keys.
    class Matcher
      # One thing to look for; `index` tells the patterns apart (a window with more different ones is better)
      Pattern = Struct.new(:regexp, :key_patterns, :folded, :index) do
        def applies_to?(key)
          key_patterns.nil? || key_patterns.any? { |pattern| pattern.match?(key) }
        end
      end

      WORD_CHAR = "[[:alnum:]]"

      attr_reader :patterns

      # The matcher of a parsed query (Archsight::Query::Query); empty when the query searches no text
      def self.for(query, database)
        conditions = text_conditions(query.ast)
        return new([]) if conditions.empty?

        index = TextIndex.for(database)
        patterns = conditions.flat_map do |node|
          fulltext = node.is_a?(Archsight::Query::AST::SearchTerms) || node.fulltext?
          fulltext ? term_regexps(index, node.terms).map { |re| [re, nil, true] } : [[node.regexp, node.key_patterns, false]]
        end
        new(patterns.each_with_index.map { |(re, keys, folded), i| Pattern.new(re, keys, folded, i) })
      end

      # The text conditions of a query that are not negated (sub-queries left out)
      def self.text_conditions(node, found = [])
        case node
        when Archsight::Query::AST::QueryNode then text_conditions(node.expression, found)
        when Archsight::Query::AST::BinaryOp
          text_conditions(node.left, found)
          text_conditions(node.right, found)
        when Archsight::Query::AST::TextCondition, Archsight::Query::AST::SearchTerms then found << node
        end
        found
      end

      # One regexp per word or phrase. Each word is found by its stem or as written (a prefix word such as `deploy`
      # stems to `deploi`, which `deployed` does not start with), at the start of a word
      def self.term_regexps(index, terms)
        terms.filter_map do |term|
          stems = index.stems(term)
          next if stems.empty?

          written = fold(term).downcase.scan(/[[:alnum:]]+/)
          words = stems.each_with_index.map do |stem, i|
            forms = [stem, (written[i] if written.size == stems.size)].compact.uniq
            "(?:#{forms.map { |form| Regexp.escape(form) }.join("|")})"
          end
          Regexp.new("(?<!#{WORD_CHAR})#{words.join("#{WORD_CHAR}*[^[:alnum:]]+")}#{WORD_CHAR}*", Regexp::IGNORECASE)
        end
      end

      # Accents taken off, character by character, so offsets stay those of the original text
      def self.fold(text)
        return text if text.ascii_only?

        text.each_char.map { |char| char.ascii_only? ? char : (char.unicode_normalize(:nfd)[0] || char) }.join
      end

      def initialize(patterns)
        @patterns = patterns
      end

      def empty?
        @patterns.empty?
      end

      # [[from, to, pattern index]] of every match in `text` of the annotation `key` (nil = a title), ordered
      def ranges(text, key = nil)
        folded = nil
        @patterns.flat_map do |pattern|
          next [] unless key.nil? ? pattern.key_patterns.nil? : pattern.applies_to?(key)

          subject = pattern.folded ? (folded ||= self.class.fold(text)) : text
          subject.to_enum(:scan, pattern.regexp).filter_map do
            match = Regexp.last_match
            [match.begin(0), match.end(0), pattern.index] if match.end(0) > match.begin(0)
          end
        end.sort
      end

      # [[from, to]] to mark in a title or name
      def marks(text)
        merge(ranges(text).map { |from, to, _| [from, to] })
      end

      def merge(marks)
        marks.sort.each_with_object([]) do |(from, to), merged|
          if merged.any? && from <= merged.last[1]
            merged.last[1] = [merged.last[1], to].max
          else
            merged << [from, to]
          end
        end
      end
    end
  end
end
