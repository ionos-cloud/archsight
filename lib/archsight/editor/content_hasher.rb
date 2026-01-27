# frozen_string_literal: true

require "digest"

module Archsight
  module Editor
    # ContentHasher generates SHA256 hashes for optimistic locking
    module ContentHasher
      module_function

      # Generate a hash of YAML content for comparison
      # Normalizes line endings before hashing to ensure consistency across platforms
      # @param content [String] YAML content
      # @return [String] 16-character hex hash
      def hash(content)
        normalized = content.gsub("\r\n", "\n").gsub("\r", "\n")
        Digest::SHA256.hexdigest(normalized)[0, 16]
      end

      # Validate that content hasn't changed since expected_hash was computed
      # @param path [String] File path
      # @param start_line [Integer] Line number where document starts
      # @param expected_hash [String, nil] Expected content hash
      # @return [Hash, nil] Error hash with :conflict and :error keys, or nil if valid
      def validate(path:, start_line:, expected_hash:)
        return nil unless expected_hash

        current_content = FileWriter.read_document(path: path, start_line: start_line)
        current_hash = hash(current_content)

        return nil if current_hash == expected_hash

        { conflict: true, error: "Conflict: The resource has been modified. Please reload the page and try again." }
      end
    end
  end
end
