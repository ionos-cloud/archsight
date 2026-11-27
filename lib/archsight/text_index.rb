# frozen_string_literal: true

require "sqlite3"
require_relative "query/errors"

module Archsight
  # Full-text index of the resources: an in-memory SQLite FTS5 table next to the model. It is contentless (only the
  # index is kept, not a second copy of the text), one row per resource with two columns: `names` (name, aliases,
  # titles) and `body` (every other string annotation). Queries answer resource => relevance (bm25, higher is better).
  # Built by Database#text_index on first use and dropped on reload.
  class TextIndex
    # bm25 weights of the columns: a word in the name or title counts as much as ten in the body
    COLUMN_WEIGHTS = [10.0, 1.0].freeze
    NAME_KEYS = %w[architecture/aliases architecture/title page/title].freeze
    TOKENIZER = "porter unicode61 remove_diacritics 2"

    attr_reader :size

    # The index of `database`: the one it keeps (Database#text_index), else a fresh one (test doubles)
    def self.for(database)
      database.respond_to?(:text_index) ? database.text_index : new(database)
    end

    def initialize(database)
      @resources = []
      @mutex = Mutex.new
      @db = SQLite3::Database.new(":memory:")
      @db.execute("CREATE VIRTUAL TABLE fts USING fts5(names, body, content='', tokenize='#{TOKENIZER}')")
      # a scratch table with the same tokenizer: what the index makes of a word (its stem), for highlighting
      @db.execute("CREATE VIRTUAL TABLE stems USING fts5(text, tokenize='#{TOKENIZER}')")
      @db.execute("CREATE VIRTUAL TABLE stems_vocab USING fts5vocab(stems, 'instance')")
      build(database)
      @size = @resources.size
    end

    # Resource => score (higher is more relevant) for an FTS5 match expression (see Expression.translate)
    # @raise [Archsight::Query::QueryError] if SQLite rejects the expression
    def search(expression)
      rows = @mutex.synchronize do
        @db.execute("SELECT rowid, bm25(fts, #{COLUMN_WEIGHTS.join(", ")}) FROM fts WHERE fts MATCH ?", [expression])
      end
      rows.to_h { |rowid, score| [@resources[rowid - 1], -score] }
    rescue SQLite3::SQLException => e
      raise Archsight::Query::QueryError.new("Invalid text search #{expression.inspect}: #{e.message}", position: 0, source: nil)
    end

    # The tokens the index makes of `text`, in order: lowercase, without accents, stemmed ("Failovers" -> "failov")
    def stems(text)
      @mutex.synchronize do
        @db.execute("INSERT INTO stems(rowid, text) VALUES (1, ?)", [text.to_s])
        tokens = @db.execute("SELECT term FROM stems_vocab WHERE doc = 1 ORDER BY offset").map(&:first)
        @db.execute("DELETE FROM stems WHERE rowid = 1")
        tokens
      end
    end

    private

    def build(database)
      @db.transaction do
        insert = @db.prepare("INSERT INTO fts(rowid, names, body) VALUES (?, ?, ?)")
        database.instances.each_value do |by_name|
          by_name.each_value do |instance|
            @resources << instance
            names, body = columns(instance)
            insert.execute(@resources.size, names, body)
          end
        end
        insert.close
      end
    end

    def columns(instance)
      names = [instance.name.to_s]
      body = []
      instance.annotations.each do |key, value|
        next unless value.is_a?(String)

        (NAME_KEYS.include?(key) ? names : body) << value
      end
      [names.join("\n"), body.join("\n")]
    end
  end
end

require_relative "text_index/expression"
require_relative "text_index/weights"
require_relative "text_index/matcher"
require_relative "text_index/snippets"
