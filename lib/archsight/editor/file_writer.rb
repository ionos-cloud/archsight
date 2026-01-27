# frozen_string_literal: true

module Archsight
  class Editor
    # FileWriter handles writing YAML documents back to multi-document files
    module FileWriter
      class WriteError < StandardError; end

      # Replace a YAML document in a file starting at a given line
      # @param path [String] File path
      # @param start_line [Integer] Line number where document starts (1-indexed)
      # @param new_yaml [String] New YAML content (without leading ---)
      # @raise [WriteError] if file cannot be written or document not found at expected line
      def self.replace_document(path:, start_line:, new_yaml:)
        raise WriteError, "File not found: #{path}" unless File.exist?(path)
        raise WriteError, "File not writable: #{path}" unless File.writable?(path)

        lines = File.readlines(path)
        start_idx = start_line - 1 # Convert to 0-indexed

        raise WriteError, "Line #{start_line} is beyond end of file" if start_idx >= lines.length

        # Find the end of this document (next --- or EOF)
        end_idx = find_document_end(lines, start_idx)

        # Build the new content
        # Ensure new_yaml ends with a newline
        new_yaml = "#{new_yaml}\n" unless new_yaml.end_with?("\n")

        # Replace the document
        new_lines = lines[0...start_idx] + [new_yaml] + lines[end_idx..]

        # Write atomically by writing to temp file then renaming
        File.write(path, new_lines.join)
      end

      # Find the end index of a document (the line index of the next --- or EOF)
      # @param lines [Array<String>] File lines
      # @param start_idx [Integer] Starting line index (0-indexed)
      # @return [Integer] End index (exclusive - the line after the document ends)
      def self.find_document_end(lines, start_idx)
        # Start searching from the line after start_idx
        idx = start_idx + 1

        while idx < lines.length
          # Check if this line is a document separator
          return idx if lines[idx].strip == "---"

          idx += 1
        end

        # No separator found, document goes to EOF
        lines.length
      end
    end
  end
end
