# frozen_string_literal: true

require "fileutils"

# Thread-safe file writer for concurrent import handlers
#
# Manages shared output files that multiple handlers can write to.
# Content is buffered in memory and sorted by key when close_all is called.
#
# @example
#   writer = SharedFileWriter.new
#   writer.append_yaml("/path/to/output.yaml", yaml_content, sort_key: "Repo:name")
#   writer.close_all  # Sorts and writes buffered content
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
  def append_yaml(path, content, sort_key: nil)
    @mutex.synchronize do
      @files[path] ||= { entries: [], lock: Mutex.new }
    end

    entry = @files[path]
    entry[:lock].synchronize do
      entry[:entries] << { key: sort_key, content: content }
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

    # Sort by key (nil keys go last)
    sorted = entries.sort_by { |e| e[:key] || "\xFF" }

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
end
