# frozen_string_literal: true

require "fileutils"
require "yaml"

# Thread-safe file writer for concurrent import handlers
#
# Manages shared output files that multiple handlers can write to.
# Content is buffered in memory and sorted by key when close_all is called.
#
# When a file is flushed, any document already on disk whose producer isn't
# among this flush's fresh producers is carried forward unchanged - this is
# what lets a cached (skipped) import's previously-generated output, or
# another task's output from an earlier iteration of the same run, survive
# being flushed to a shared output file instead of getting silently wiped.
#
# @example
#   writer = SharedFileWriter.new
#   writer.append_yaml("/path/to/output.yaml", yaml_content, sort_key: "Repo:name", producer: "Import:Repo:name")
#   writer.close_all  # Sorts and writes buffered content, merged with existing content
class Archsight::Import::SharedFileWriter
  def initialize
    @mutex = Mutex.new
    @files = {}
  end

  # Append YAML content to a file (thread-safe, buffered)
  # Content is sorted by sort_key when close_all is called
  #
  # @param path [String] Full path to the output file
  # @param content [String] YAML content to append
  # @param sort_key [String, nil] Key for sorting (nil keys go last)
  # @param producer [String, nil] Name of the Import task that produced this
  #   content, used to decide what existing on-disk content this entry may
  #   supersede when the file is flushed
  def append_yaml(path, content, sort_key: nil, producer: nil)
    @mutex.synchronize do
      @files[path] ||= { entries: [], lock: Mutex.new }
    end

    entry = @files[path]
    entry[:lock].synchronize do
      entry[:entries] << { key: sort_key, content: content, producer: producer }
    end
  end

  # Close all files - sorts and writes buffered content
  def close_all
    @mutex.synchronize do
      @files.each do |path, entry|
        write_sorted_file(path, entry[:entries])
      end
      @files.clear
    end
  end

  private

  def write_sorted_file(path, entries)
    return if entries.empty?

    FileUtils.mkdir_p(File.dirname(path))

    fresh_producers = entries.filter_map { |e| e[:producer] }.uniq
    all_entries = preserved_entries(path, fresh_producers) + entries

    # Sort by key (nil keys go last)
    sorted = all_entries.sort_by { |e| e[:key] || "\xFF" }

    File.open(path, "w") do |file|
      sorted.each_with_index do |entry, idx|
        content = entry[:content]
        # Add document separator if not first and content doesn't have one
        file.write("---\n") if idx.positive? && !content.start_with?("---")
        file.write(content)
        file.write("\n") unless content.end_with?("\n")
      end
    end
  end

  # Documents already on disk whose producer isn't among this flush's fresh
  # producers are carried forward unchanged, keyed by their own producer so
  # a producer that does write fresh content later in the same run replaces
  # its own prior output rather than duplicating it. Content is kept as its
  # original raw text (not re-dumped), so anything preserved is byte-for-byte
  # identical to what was already on disk.
  def preserved_entries(path, fresh_producers)
    return [] unless File.exist?(path)

    split_yaml_documents(File.read(path)).filter_map do |raw|
      doc = YAML.safe_load(raw, permitted_classes: [Time])
      next nil unless doc.is_a?(Hash)

      producer = document_producer(doc)
      next nil if producer.nil? || fresh_producers.include?(producer)

      { key: producer, content: raw, producer: producer }
    rescue Psych::SyntaxError
      nil
    end
  end

  def document_producer(doc)
    doc.dig("metadata", "annotations", "generated/script") ||
      (doc["kind"] == "Import" ? doc.dig("metadata", "name") : nil)
  end

  def split_yaml_documents(text)
    text.split(/^---\s*$/).map(&:strip).reject(&:empty?)
  end
end
